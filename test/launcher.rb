# frozen_string_literal: true

require_relative "helper"
require "sidekiq/launcher"

describe Sidekiq::Launcher do
  subject do
    Sidekiq::Launcher.new(@config)
  end

  before do
    @config = reset!
    @config.default_capsule.concurrency = 3
    @config[:tag] = "myapp"
  end

  describe "memory collection" do
    it "works in any test environment" do
      kb = Sidekiq::Launcher::MEMORY_GRABBER.call($$)
      refute_nil kb
      assert kb > 0
    end
  end

  it "starts and stops" do
    subject.run
    subject.stop
  end

  describe "heartbeat" do
    before do
      @id = subject.identity

      Sidekiq::Processor::WORK_STATE.set("a", {"b" => 1})

      @proctitle = $0
    end

    after do
      Sidekiq::Processor::WORK_STATE.clear
      $0 = @proctitle
    end

    describe "#heartbeat" do
      describe "run" do
        it "sets sidekiq version, tag and the number of busy workers to proctitle" do
          subject.heartbeat

          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [1 of 3 busy]", $0
        end

        it "stores process info in redis" do
          subject.heartbeat

          workers, rtt = @config.redis { |c| c.hmget(subject.identity, "busy", "rtt_us") }

          assert_equal "1", workers
          refute_nil rtt
          assert_in_delta 1000, rtt.to_i, 1000

          expires = @config.redis { |c| c.pttl(subject.identity) }

          assert_in_delta 60000, expires, 500
        end

        describe "events" do
          before do
            @cnt = 0

            @config.on(:heartbeat) do
              @cnt += 1
            end
          end

          it "fires start heartbeat event only once" do
            assert_equal 0, @cnt
            subject.heartbeat
            assert_equal 1, @cnt
            subject.heartbeat
            assert_equal 1, @cnt
          end
        end
      end

      describe "quiet" do
        before do
          subject.quiet
        end

        it "sets stopping proctitle" do
          subject.heartbeat

          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [1 of 3 busy] stopping", $0
        end

        it "stores process info in redis" do
          subject.heartbeat

          info = @config.redis { |c| c.hmget(subject.identity, "busy") }

          assert_equal ["1"], info

          expires = @config.redis { |c| c.pttl(subject.identity) }

          assert_in_delta 60000, expires, 50
        end
      end

      it "fires new heartbeat events" do
        i = 0
        @config.on(:heartbeat) do
          i += 1
        end
        assert_equal 0, i
        subject.heartbeat
        assert_equal 1, i
        subject.heartbeat
        assert_equal 1, i
      end

      describe "when manager is active" do
        before do
          Sidekiq::Launcher::PROCTITLES << proc { "xyz" }
          subject.heartbeat
          Sidekiq::Launcher::PROCTITLES.pop
        end

        it "sets useful info to proctitle" do
          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [1 of 3 busy] xyz", $0
        end

        it "stores process info in redis" do
          info = @config.redis { |c| c.hmget(@id, "busy") }
          assert_equal ["1"], info
          expires = @config.redis { |c| c.pttl(@id) }
          assert_in_delta 60000, expires, 500
        end
      end
    end

    describe "when manager is stopped" do
      before do
        subject.quiet
        subject.heartbeat
      end

      # after do
      # puts system('redis-cli -n 15 keys  "*" | while read LINE ; do TTL=`redis-cli -n 15 ttl "$LINE"`; if [ "$TTL" -eq -1 ]; then echo "$LINE"; fi; done;')
      # end

      it "indicates stopping status in proctitle" do
        assert_equal "sidekiq #{Sidekiq::VERSION} myapp [1 of 3 busy] stopping", $0
      end

      it "stores process info in redis" do
        info = @config.redis { |c| c.hmget(@id, "busy") }
        assert_equal ["1"], info
        expires = @config.redis { |c| c.pttl(@id) }
        assert_in_delta 60000, expires, 50
      end
    end
  end
end
