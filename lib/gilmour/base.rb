# encoding: utf-8
# This is required to check whether Mash class already exists
def class_exists?(class_name)
  klass = Module.const_get(class_name)
  return klass.is_a?(Class)
rescue NameError
  return false
end

require 'logger'
require 'securerandom'
require 'json'
require 'mash' unless class_exists? 'Mash'
require 'eventmachine'
require_relative 'protocol'
require_relative 'responder'
require_relative 'backends/backend'

# The Gilmour module
module Gilmour

  LoggerLevels = {
    unknown: Logger::UNKNOWN,
    fatal: Logger::FATAL,
    error: Logger::ERROR,
    warn: Logger::WARN,
    info: Logger::INFO,
    debug: Logger::DEBUG
  }


  GLogger = Logger.new(STDERR)
  EnvLoglevel =  ENV["LOG_LEVEL"] ? ENV["LOG_LEVEL"].to_sym : :warn
  GLogger.level = LoggerLevels[EnvLoglevel] || Logger::WARN

  RUNNING = false
  # This is the base module that should be included into the
  # container class
  module Base
    def self.included(base)
      base.extend(Registrar)
    end

    ######### Registration module ###########
    # This module helps act as a Resistrar for subclasses
    module Registrar
      attr_accessor :subscribers_path
      attr_accessor :backend
      DEFAULT_SUBSCRIBER_PATH = 'subscribers'
      @@subscribers = {} # rubocop:disable all
      @@registered_services = []

      def inherited(child)
        @@registered_services << child
      end

      def registered_subscribers
        @@registered_services
      end

      def listen_to(topic, excl = false)
        handler = Proc.new
        @@subscribers[topic] ||= []
        @@subscribers[topic] << { handler: handler, subscriber: self , exclusive: excl}
      end

      def subscribers(topic = nil)
        if topic
          @@subscribers[topic]
        else
          @@subscribers
        end
      end

      def load_all(dir = nil)
        dir ||= (subscribers_path || DEFAULT_SUBSCRIBER_PATH)
        Dir["#{dir}/*.rb"].each { |f| require f }
      end

      def load_subscriber(path)
        require path
      end
    end

    def registered_subscribers
      self.class.registered_subscribers
    end
    ############ End Register ###############

    class << self
      attr_accessor :backend
    end
    attr_reader :backends

    def enable_backend(name, opts = {})
      Gilmour::Backend.load_backend(name)
      @backends ||= {}
      @backends[name] ||= Gilmour::Backend.get(name).new(opts)

      backend = @backends[name]

      if opts["multi_process"] || opts[:multi_process]
        backend.multi_process = true
      end

      backend
    end
    alias_method :get_backend, :enable_backend

    def subs_grouped_by_backend
      subs_by_backend = {}
      self.class.subscribers.each do |topic, subs|
        subs.each do |sub|
          subs_by_backend[sub[:subscriber].backend] ||= {}
          subs_by_backend[sub[:subscriber].backend][topic] ||= []
          subs_by_backend[sub[:subscriber].backend][topic] << sub
        end
      end
      subs_by_backend
    end

    def start(startloop = false)
      subs_by_backend = subs_grouped_by_backend
      subs_by_backend.each do |b, subs|
        get_backend(b).setup_subscribers(subs)
      end
      if startloop
        GLogger.debug 'Joining EM event loop'
        EM.reactor_thread.join
      end
    end
  end
end
