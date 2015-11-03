require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/class/attribute_accessors'

module Sequenced
  module ActsAsSequenced
    mattr_accessor :redis
    @@redis = nil

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      # Public: Defines ActiveRecord callbacks to set a sequential ID scoped
      # on a specific class.
      #
      # options - The Hash of options for configuration:
      #           :scope    - The Symbol representing the columm on which the
      #                       sequential ID should be scoped (default: nil)
      #           :column   - The Symbol representing the column that stores the
      #                       sequential ID (default: :sequential_id)
      #           :start_at - The Integer value at which the sequence should
      #                       start (default: 1)
      #           :skip     - Skips the sequential ID generation when the lambda
      #                       expression evaluates to nil. Gets passed the
      #                       model object
      #
      # Examples
      #
      #   class Answer < ActiveRecord::Base
      #     belongs_to :question
      #     acts_as_sequenced :scope => :question_id
      #   end
      #
      # Returns nothing.
      def acts_as_sequenced(options = {})
        cattr_accessor :sequenced_options
        self.sequenced_options = options

        before_save :set_sequential_id
        include Sequenced::ActsAsSequenced::InstanceMethods
      end
    end

    module InstanceMethods
      def set_sequential_id
        scope_value = if self.class.base_class.sequenced_options[:scope]
          if self.class.base_class.sequenced_options[:scope].kind_of?(Array)
            self.class.base_class.sequenced_options[:scope].collect do |s|
              self.public_send(s)
            end.join(',')
          else
            self.public_send(self.class.base_class.sequenced_options[:scope])
          end
        else
          nil
        end
        lock_key = "#{self.class.to_s}:#{self.class.base_class.sequenced_options[:scope]}=#{scope_value}:#{self.class.base_class.sequenced_options[:column] || 'sequential_id'}"
        while redis.get(lock_key);end
        redis.set(lock_key, "1")
        redis.expire(lock_key, 30)
        Sequenced::Generator.new(self, self.class.base_class.sequenced_options).set
        redis.del(lock_key)
      end
    end
  end
end
