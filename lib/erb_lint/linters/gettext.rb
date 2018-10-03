# frozen_string_literal: true
require "set"
require 'better_html/tree/tag'
require 'active_support/core_ext/string/inflections'

module ERBLint
  module Linters
    # Checks for hardcoded strings. Useful if you want to ensure a string can be translated using i18n.
    class Gettext < Linter
      include LinterRegistry

      ForbiddenCorrector = Class.new(StandardError)
      MissingCorrector = Class.new(StandardError)

      ALLOWED_CORRECTORS = %w(
        I18nCorrector
        RuboCop::I18nCorrector
      )

      NON_TEXT_TAGS = Set.new(%w(script style xmp iframe noembed noframes listing))
      BLACK_LISTED_TEXT = Set.new(%w(&nbsp; &ensp; &emsp; &thinsp;))

      class ConfigSchema < LinterConfig
        property :corrector, accepts: Hash, required: false, default: {}
      end
      self.config_schema = ConfigSchema

      def run(processed_source)
        require 'pry'
        binding.pry

        hardcoded_strings = processed_source.ast.descendants(:erb).each_with_object([]) do |text_node, to_check|
          # next if non_text_tag?(processed_source, text_node)
          binding.pry

          offended_strings = text_node.to_a.select { |node| relevant_node(node) }
          offended_strings.each do |offended_string|
            offended_string.split("\n").each do |str|
              to_check << [text_node, str] if check_string?(str)
            end
          end
        end
        # hardcoded_strings = (
        #   processed_source
        #   .ast
          
        #   .flatten
        #   .compact
        #   .select {|node| relevant_node(node) }
        # ).each_with_object([]) do |text_node, to_check|
        #   # next if non_text_tag?(processed_source, text_node)

        #   text_node.split("\n").each do |str|
        #     to_check << [text_node, str] if check_string?(str)
        #   end
        # end

        hardcoded_strings.compact.each do |text_node, offended_str|
          range = find_range(text_node, offended_str)
          source_range = processed_source.to_source_range(range)

          add_offense(
            source_range,
            message(source_range.source)
          )
        end
      end

      def find_range(node, str)
        match = node.loc.source.match(Regexp.new(Regexp.quote(str.strip)))
        return unless match

        range_begin = match.begin(0) + node.loc.begin_pos
        range_end   = match.end(0) + node.loc.begin_pos
        (range_begin...range_end)
      end

      def autocorrect(processed_source, offense)
        string = offense.source_range.source
        return unless klass = load_corrector
        return unless string.strip.length > 1

        corrector = klass.new(processed_source.filename, offense.source_range)
        node = RuboCop::AST::StrNode.new(:str, [string])
        corrector.autocorrect(node, tag_start: '<%= ', tag_end: ' %>')
      rescue MissingCorrector
        nil
      end

      private

      def check_string?(str)
        regex = /(_\('.*?'\))/
        string.match(regex) && !BLACK_LISTED_TEXT.include?(string)
      end

      def load_corrector
        corrector_name = @config['corrector'].fetch('name') { raise MissingCorrector }
        raise ForbiddenCorrector unless ALLOWED_CORRECTORS.include?(corrector_name)
        require @config['corrector'].fetch('path') { raise MissingCorrector }

        corrector_name.safe_constantize
      end

      # def non_text_tag?(processed_source, text_node)
      #   ast = processed_source.parser.ast.to_a
      #   index = ast.find_index(text_node)

      #   previous_node = ast[index - 1]

      #   if previous_node.type == :tag
      #     tag = BetterHtml::Tree::Tag.from_node(previous_node)

      #     NON_TEXT_TAGS.include?(tag.name) && !tag.closing?
      #   end
      # end

      def relevant_node(inner_node)
        require 'pry'
        if inner_node.type == :code
          binding.pry
          inner_node.strip.empty? ? false : inner_node
        else
          false
        end
      end

      def message(string)
        stripped_string = string.strip

        "String not translated: #{stripped_string}"
      end
    end
  end
end
