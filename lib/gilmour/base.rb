# encoding: utf-8
require 'amqp'
require 'securerandom'
require 'json'
require 'mash'
require_relative 'protocol'
require_relative 'responder'

# The Gilmour module
module Gilmour
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

      def listen_to(topic)
        handler = Proc.new
        @@subscribers[topic] ||= []
        @@subscribers[topic] << { handler: handler, subscriber: self }
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

    class Backend
      @@dir = {}

      def self.implements(token)
        @@dir[token] = self
      end

      def self.get(token)
        @@dir[token]
      end

      Dir["#{File.expand_path("../backends", __FILE__)}/*.rb"].each do |f|
        require f
      end
    end

    class << self
      attr_accessor :backend
    end
    attr_reader :backends

    def backend(name, opts = {})
      @backends ||= {}
      @backends[name] ||= Backend.get(name).new(opts)
    end

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

    def start
      subs_by_backend = subs_grouped_by_backend
      subs_by_backend.each do |b, subs|
        backend(b).start(subs)
      end
    end
  end
end
