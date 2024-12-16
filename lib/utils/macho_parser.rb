require 'macho'

module EmergeCLI
  class MachOParser
    TYPE_METADATA_KIND_MASK = 0x7 << 3
    TYPE_METADATA_KIND_SHIFT = 3

    # Bind Codes
    BIND_OPCODE_MASK = 0xF0
    BIND_IMMEDIATE_MASK = 0x0F
    BIND_OPCODE_DONE = 0x00
    BIND_OPCODE_SET_DYLIB_ORDINAL_IMM = 0x10
    BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB = 0x20
    BIND_OPCODE_SET_DYLIB_SPECIAL_IMM = 0x30
    BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM = 0x40
    BIND_OPCODE_SET_TYPE_IMM = 0x50
    BIND_OPCODE_SET_ADDEND_SLEB = 0x60
    BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB = 0x70
    BIND_OPCODE_ADD_ADDR_ULEB = 0x80
    BIND_OPCODE_DO_BIND = 0x90
    BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB = 0xA0
    BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED = 0xB0
    BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB = 0xC0

    UINT64_SIZE = 8
    UINT64_MAX_VALUE = 0xFFFFFFFFFFFFFFFF

    def load_binary(binary_path)
      @macho_file = MachO::MachOFile.new(binary_path)
      @binary_data = File.binread(binary_path)
    end

    def read_linkedit_data_command
      chained_fixups_command = nil
      @macho_file.load_commands.each do |lc|
        chained_fixups_command = lc if lc.type == :LC_DYLD_CHAINED_FIXUPS
      end

      if chained_fixups_command.nil?
        Logger.debug 'No LC_DYLD_CHAINED_FIXUPS found'
        return false, []
      end

      # linkedit_data_command
      _, _, dataoff, datasize = @binary_data[chained_fixups_command.offset, 16].unpack('L<L<L<L<')

      header = @binary_data[dataoff, datasize].unpack('L<L<L<L<L<L<L<')
      # dyld_chained_fixups_header
      _, _, imports_offset, symbols_offset, imports_count,
        imports_format, = header

      imports_start = dataoff + imports_offset
      symbols_start = dataoff + symbols_offset

      imported_symbols = []

      import_size, name_offset_proc =
        case imports_format
        when 1, nil # DYLD_CHAINED_IMPORT
          [4, ->(ptr) { ptr.unpack1('L<') >> 9 }]
        when 2 # DYLD_CHAINED_IMPORT_ADDEND
          [8, ->(ptr) { ptr.unpack1('L<') >> 9 }]
        when 3 # DYLD_CHAINED_IMPORT_ADDEND64
          [16, ->(ptr) { ptr.unpack1('Q<') >> 32 }]
        end

      # Extract imported symbol names
      imports_count.times do |i|
        import_offset = imports_start + (i * import_size)
        name_offset = name_offset_proc.call(@binary_data[import_offset, import_size])
        name_start = symbols_start + name_offset
        name = read_null_terminated_string(@binary_data[name_start..])
        imported_symbols << name
      end

      [true, imported_symbols]
    end

    def read_dyld_info_only_command
      dyld_info_only_command = nil
      @macho_file.load_commands.each do |lc|
        dyld_info_only_command = lc if lc.type == :LC_DYLD_INFO_ONLY
      end

      if dyld_info_only_command.nil?
        Logger.debug 'No LC_DYLD_INFO_ONLY found'
        return []
      end

      bound_symbols = []
      start_address = dyld_info_only_command.bind_off
      end_address = dyld_info_only_command.bind_off + dyld_info_only_command.bind_size
      current_address = start_address

      current_symbol = BoundSymbol.new(segment_offset: 0, library: nil, offset: 0, symbol: '')
      while current_address < end_address
        results, current_address, current_symbol = read_next_symbol(@binary_data, current_address, end_address,
                                                                    current_symbol)

        # Dup items to avoid pointer issues
        results.each do |res|
          bound_symbols << res.dup
        end
      end

      # Filter only swift symbols starting with _$s
      swift_symbols = bound_symbols.select { |bound_symbol| bound_symbol.symbol.start_with?('_$s') }

      load_commands = @macho_file.load_commands.select { |lc| lc.type == :LC_SEGMENT_64 || lc.type == :LC_SEGMENT } # rubocop:disable Naming/VariableNumber

      swift_symbols.each do |swift_symbol|
        swift_symbol.address = load_commands[swift_symbol.segment_offset].vmaddr + swift_symbol.offset
      end

      swift_symbols
    end

    def find_protocols_in_swift_proto(use_chained_fixups, imported_symbols, bound_symbols, search_symbols)
      found_section = nil
      @macho_file.segments.each do |segment|
        segment.sections.each do |section|
          if section.segname.strip == '__TEXT' && section.sectname.strip == '__swift5_proto'
            found_section = section
            break
          end
        end
      end

      unless found_section
        Logger.error 'The __swift5_proto section was not found.'
        return false
      end

      start = found_section.offset
      size = found_section.size
      offsets_list = parse_list(@binary_data, start, size)

      offsets_list.each do |relative_offset, offset_start|
        type_file_address = offset_start + relative_offset
        if type_file_address <= 0 || type_file_address >= @binary_data.size
          Logger.error 'Invalid protocol conformance offset'
          next
        end

        # ProtocolConformanceDescriptor -> ProtocolDescriptor
        protocol_descriptor = read_little_endian_signed_integer(@binary_data, type_file_address)

        # # ProtocolConformanceDescriptor -> ConformanceFlags
        conformance_flags = read_little_endian_signed_integer(@binary_data, type_file_address + 12)
        kind = (conformance_flags & TYPE_METADATA_KIND_MASK) >> TYPE_METADATA_KIND_SHIFT

        next unless kind == 0

        indirect_relative_offset = get_indirect_relative_offset(type_file_address, protocol_descriptor)

        bound_symbol = bound_symbols.find { |symbol| symbol.address == indirect_relative_offset }
        if bound_symbol
          return true if search_symbols.include?(bound_symbol.symbol)
        elsif use_chained_fixups
          descriptor_offset = protocol_descriptor & ~1
          jump_ptr = type_file_address + descriptor_offset

          address = @binary_data[jump_ptr, 4].unpack1('I<')
          symbol_name = imported_symbols[address]
          return true if search_symbols.include?(symbol_name)
        end
      end
      false
    end

    private

    def read_next_symbol(binary_data, current_address, end_address, current_symbol)
      while current_address < end_address
        first_byte = read_byte(binary_data, current_address)
        current_address += 1
        immediate = first_byte & BIND_IMMEDIATE_MASK
        opcode = first_byte & BIND_OPCODE_MASK

        case opcode
        when BIND_OPCODE_DONE
          result = current_symbol.dup
          current_symbol.segment_offset = 0
          current_symbol.library = 0
          current_symbol.offset = 0
          current_symbol.symbol = ''
          return [result], current_address, current_symbol
        when BIND_OPCODE_SET_DYLIB_ORDINAL_IMM
          current_symbol.library = [immediate].pack('L').unpack1('L')
        when BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM
          current_symbol.symbol = read_null_terminated_string(binary_data[current_address..])
          # Increase current pointer
          current_address += current_symbol.symbol.size + 1
        when BIND_OPCODE_ADD_ADDR_ULEB
          offset, new_current_address = read_uleb(@binary_data, current_address)
          current_symbol.offset = (current_symbol.offset + offset) & UINT64_MAX_VALUE
          current_address = new_current_address
        when BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB
          offset, new_current_address = read_uleb(@binary_data, current_address)
          current_symbol.offset = (current_symbol.offset + offset + UINT64_SIZE) & UINT64_MAX_VALUE
          current_address = new_current_address
          return [current_symbol], current_address, current_symbol
        when BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB
          offset, current_address = read_uleb(@binary_data, current_address)
          current_symbol.segment_offset = immediate
          current_symbol.offset = offset
        when BIND_OPCODE_SET_ADDEND_SLEB
          _, current_address = read_uleb(@binary_data, current_address)
        when BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED
          result = current_symbol.dup
          current_symbol.offset = (
            current_symbol.offset + (immediate * UINT64_SIZE) + UINT64_SIZE
          ) & UINT64_MAX_VALUE
          return [result], current_address, current_symbol
        when BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB
          count, current_address = read_uleb(@binary_data, current_address)
          skipping, current_address = read_uleb(@binary_data, current_address)

          results = []
          count.times do
            results << current_symbol.dup
            current_symbol.offset = (current_symbol.offset + skipping + UINT64_SIZE) & UINT64_MAX_VALUE
          end

          return results, current_address, current_symbol
        when BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB
          count, current_address = read_uleb(@binary_data, current_address)
          current_symbol.library = count
        when BIND_OPCODE_DO_BIND
          result = current_symbol.dup
          current_symbol.offset = (current_symbol.offset + UINT64_SIZE) & UINT64_MAX_VALUE
          return [result], current_address, current_symbol
        end
      end
      [[], current_address, current_symbol]
    end

    def read_byte(binary_data, address)
      binary_data[address, 1].unpack1('C')
    end

    def read_little_endian_signed_integer(binary_data, address)
      binary_data[address, 4].unpack1('l<')
    end

    def read_uleb(binary_data, address)
      next_byte = 0
      size = 0
      result = 0

      loop do
        next_byte = read_byte(binary_data, address)
        address += 1
        bytes = next_byte & 0x7F
        shifted = bytes << (size * 7)

        size += 1
        result |= shifted
        break if next_byte.nobits?(0x80)
      end

      [result, address]
    end

    def read_null_terminated_string(data)
      data.unpack1('Z*')
    end

    def vm_address(file_offset, macho)
      load_commands = macho.load_commands.select { |lc| lc.type == :LC_SEGMENT_64 || lc.type == :LC_SEGMENT } # rubocop:disable Naming/VariableNumber
      load_commands.each do |lc|
        next unless file_offset >= lc.fileoff && file_offset < (lc.fileoff + lc.filesize)
        unless lc.respond_to?(:sections)
          Logger.error 'Load command does not support sections function'
          next
        end

        lc.sections.each do |section|
          if file_offset >= section.offset && file_offset < (section.offset) + section.size
            return section.addr + (file_offset - section.offset)
          end
        end
      end
      nil
    end

    def parse_list(bytes, start, size)
      data_pointer = bytes[start..]
      file_offset = start
      pointer_size = 4
      class_pointers = []

      (size / pointer_size).to_i.times do
        pointer = data_pointer.unpack1('l<')
        class_pointers << [pointer, file_offset]
        data_pointer = data_pointer[pointer_size..]
        file_offset += pointer_size
      end

      class_pointers
    end

    def get_indirect_relative_offset(type_file_address, protocol_descriptor)
      vm_start = vm_address(type_file_address, @macho_file)
      return nil if vm_start.nil?
      if (vm_start + protocol_descriptor).odd?
        (vm_start + protocol_descriptor) & ~1
      elsif vm_start + protocol_descriptor > 0
        vm_start + protocol_descriptor
      end
    end
  end

  class BoundSymbol
    attr_accessor :segment_offset, :library, :offset, :symbol, :address

    def initialize(segment_offset:, library:, offset:, symbol:)
      @segment_offset = segment_offset
      @library = library
      @offset = offset
      @symbol = symbol
      @address = 0
    end
  end
end
