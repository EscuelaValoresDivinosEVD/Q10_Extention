ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Stub temporal para reemplazar un método de clase durante un bloque (compatible con Minitest).
    def stub_class_method(klass, method_name, return_value, &block)
      original = klass.method(method_name)
      klass.define_singleton_method(method_name) { |*_args, **_kwargs| return_value }
      block.call
    ensure
      klass.define_singleton_method(method_name) { |*args, **kwargs| original.call(*args, **kwargs) }
    end
  end
end
