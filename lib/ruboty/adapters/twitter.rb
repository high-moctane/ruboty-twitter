require "active_support/core_ext/object/try"
require "mem"
require "twitter"

module Ruboty
  module Adapters
    class Twitter < Base
      include Mem

      MAX_MSG_LENGTH = 140

      env :TWITTER_ACCESS_TOKEN, "Twitter access token"
      env :TWITTER_ACCESS_TOKEN_SECRET, "Twitter access token secret"
      env :TWITTER_AUTO_FOLLOW_BACK, "Pass 1 to follow back followers (optional)", optional: true
      env :TWITTER_CONSUMER_KEY, "Twitter consumer key (a.k.a. API key)"
      env :TWITTER_CONSUMER_SECRET, "Twitter consumer secret (a.k.a. API secret)"

      def run
        Ruboty.logger.debug("#{self.class}##{__method__} started")
        abortable
        listen
        Ruboty.logger.debug("#{self.class}##{__method__} finished")
      end

      def say(message)
        id           = message[:original][:tweet].try(:id)
        repry_header = message[:to].nil? ? "" : "@#{message[:to]}\n"
        body_length  = MAX_MSG_LENGTH - repry_header.size - random_footer.size
        message[:body].scan(/.{1,#{body_length}}/m).each do |body|
          status = client.update(repry_header + body + random_footer, in_reply_to_status_id: id)
          id = status.id
          sleep 0.2
        end
      rescue => e
        Ruboty.logger.error("Twitter post error: #{e.message}")
      end

      private

      def enabled_to_auto_follow_back?
        ENV["TWITTER_AUTO_FOLLOW_BACK"] == "1"
      end

      def listen
        stream.user do |message|
          case message
          when ::Twitter::Tweet
            retweeted = message.retweeted_status.is_a?(::Twitter::Tweet)
            tweet = retweeted ? message.retweeted_status : message
            Ruboty.logger.debug("#{tweet.user.screen_name} tweeted #{tweet.text.inspect}")
            robot.receive(
              body: tweet.text,
              from: tweet.user.screen_name,
              tweet: message
            )
          when ::Twitter::Streaming::Event
            if message.name == :follow
              Ruboty.logger.debug("#{message.source.screen_name} followed #{message.target.screen_name}")
              if enabled_to_auto_follow_back? && message.target.screen_name == robot.name
                Ruboty.logger.debug("Trying to follow back #{message.source.screen_name}")
                client.follow(message.source.screen_name)
              end
            end
          end
        end
      end

      def client
        ::Twitter::REST::Client.new do |config|
          config.consumer_key        = ENV["TWITTER_CONSUMER_KEY"]
          config.consumer_secret     = ENV["TWITTER_CONSUMER_SECRET"]
          config.access_token        = ENV["TWITTER_ACCESS_TOKEN"]
          config.access_token_secret = ENV["TWITTER_ACCESS_TOKEN_SECRET"]
        end
      end
      memoize :client

      def stream
        ::Twitter::Streaming::Client.new do |config|
          config.consumer_key        = ENV["TWITTER_CONSUMER_KEY"]
          config.consumer_secret     = ENV["TWITTER_CONSUMER_SECRET"]
          config.access_token        = ENV["TWITTER_ACCESS_TOKEN"]
          config.access_token_secret = ENV["TWITTER_ACCESS_TOKEN_SECRET"]
        end
      end
      memoize :stream

      def abortable
        Thread.abort_on_exception = true
      end

      def random_footer
        " #{[*0..9].sample(3).join}"
      end
    end
  end
end
