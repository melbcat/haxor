module Haxor
  class Linker
    attr_accessor :stack

    SECTIONS = [:text, :data, :bss]

    def initialize
      @cpu = Vm::Cpu::Core.new
      @units = []
      @tokens = []
      @labels = @cpu.labels.clone
      @stack = 4096
    end

    def load_unit(filename)
      @units << Haxor::Compiler::Unit.load(filename)
    end

    def link(filename)
      calc_absolute_addr
      collect_labels
      unwind_pointers

      output = File.open(filename, 'wb')
      output.write build
      output.close
    end

    private

    def walk_tokens(type = nil)
      SECTIONS.each do |section|
        @units.each do |unit|
          unit.section = section
          unit.tokens.each do |token|
            next unless type.nil? || token.is_a?(type)
            yield token, section
          end
        end
      end
    end

    def calc_absolute_addr
      addr = Consts::RESERVED_MEM
      walk_tokens do |token|
        token.absolute_addr = addr
        addr += token.size
      end
    end

    def collect_labels
      walk_tokens(Token::Label) do |token|
        fail "Label already exists: #{token.label}." if @labels.key? token.label
        @labels[token.label] = token
      end
    end

    def unwind_pointers
      walk_tokens(Token::Pointer) do |token|
        fail "Label not found: #{token.label}." unless @labels.key? token.label
        token.data = @labels[token.label].absolute_addr
      end
    end

    def build_header
      bss_size = 0
      walk_tokens do |token, section|
        bss_size += token.size if section == :bss
      end

      hdr = Header.new
      hdr.version = Consts::VERSION
      hdr.entry_point = @labels['main'].absolute_addr
      hdr.stack_size = @stack
      hdr.bss_size = bss_size
      hdr
    end

    def build
      result = build_header.dump
      walk_tokens do |token, section|
        next unless [:text, :data].include? section
        puts "[#{section}] [#{token.absolute_addr}] #{token}"
        result << token.to_bytecode
      end
      result
    end
  end
end
