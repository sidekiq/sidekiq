# frozen_string_literal: true

require_relative "helper"
require "sidekiq/sd_notify"
require "tmpdir"

describe Sidekiq::SdNotify do
  # Bind a UNIX datagram socket and point NOTIFY_SOCKET at it, so we can
  # assert on exactly what SdNotify writes.
  def with_notify_socket
    Dir.mktmpdir do |dir|
      path = File.join(dir, "notify.sock")
      server = Socket.new(:UNIX, :DGRAM)
      server.bind(Socket.pack_sockaddr_un(path))
      old = ENV["NOTIFY_SOCKET"]
      ENV["NOTIFY_SOCKET"] = path
      begin
        yield server
      ensure
        ENV["NOTIFY_SOCKET"] = old
        server.close
      end
    end
  end

  def read(server)
    server.recvfrom(256).first
  end

  describe ".notify" do
    it "returns nil when NOTIFY_SOCKET is unset" do
      old = ENV.delete("NOTIFY_SOCKET")
      begin
        assert_nil Sidekiq::SdNotify.notify("READY=1")
      ensure
        ENV["NOTIFY_SOCKET"] = old if old
      end
    end

    it "writes the state to the notification socket" do
      with_notify_socket do |server|
        Sidekiq::SdNotify.notify("STATUS=working")
        assert_equal "STATUS=working", read(server)
      end
    end

    it "leaves NOTIFY_SOCKET in the environment by default" do
      with_notify_socket do |_server|
        Sidekiq::SdNotify.notify("READY=1")
        refute_nil ENV["NOTIFY_SOCKET"]
      end
    end

    it "removes NOTIFY_SOCKET from the environment when unset_env is true" do
      with_notify_socket do |_server|
        Sidekiq::SdNotify.notify("READY=1", true)
        assert_nil ENV["NOTIFY_SOCKET"]
      end
    end

    it "raises NotifyError when the socket cannot be reached" do
      old = ENV["NOTIFY_SOCKET"]
      ENV["NOTIFY_SOCKET"] = "/nonexistent/does-not-exist.sock"
      begin
        assert_raises(Sidekiq::SdNotify::NotifyError) do
          Sidekiq::SdNotify.notify("READY=1")
        end
      ensure
        ENV["NOTIFY_SOCKET"] = old
      end
    end
  end

  describe "state helpers" do
    {
      ready: "READY=1",
      stopping: "STOPPING=1",
      reloading: "RELOADING=1",
      watchdog: "WATCHDOG=1",
      fdstore: "FDSTORE=1"
    }.each do |meth, payload|
      it "##{meth} writes #{payload}" do
        with_notify_socket do |server|
          Sidekiq::SdNotify.public_send(meth)
          assert_equal payload, read(server)
        end
      end
    end

    it "#status writes STATUS=<string>" do
      with_notify_socket do |server|
        Sidekiq::SdNotify.status("draining")
        assert_equal "STATUS=draining", read(server)
      end
    end

    it "#errno writes ERRNO=<int>" do
      with_notify_socket do |server|
        Sidekiq::SdNotify.errno(3)
        assert_equal "ERRNO=3", read(server)
      end
    end

    it "#mainpid writes MAINPID=<int>" do
      with_notify_socket do |server|
        Sidekiq::SdNotify.mainpid(4242)
        assert_equal "MAINPID=4242", read(server)
      end
    end
  end

  describe ".watchdog?" do
    def with_env(vars)
      old = {}
      vars.each do |k, v|
        old[k] = ENV[k]
        v.nil? ? ENV.delete(k) : ENV[k] = v
      end
      yield
    ensure
      old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    it "is false when WATCHDOG_USEC is unset" do
      with_env("WATCHDOG_USEC" => nil, "WATCHDOG_PID" => nil) do
        refute Sidekiq::SdNotify.watchdog?
      end
    end

    it "is false when WATCHDOG_USEC is not an integer" do
      with_env("WATCHDOG_USEC" => "abc", "WATCHDOG_PID" => nil) do
        refute Sidekiq::SdNotify.watchdog?
      end
    end

    it "is false when WATCHDOG_USEC is not positive" do
      with_env("WATCHDOG_USEC" => "0", "WATCHDOG_PID" => nil) do
        refute Sidekiq::SdNotify.watchdog?
      end
    end

    it "is true when WATCHDOG_USEC is positive and WATCHDOG_PID is unset" do
      with_env("WATCHDOG_USEC" => "1000", "WATCHDOG_PID" => nil) do
        assert Sidekiq::SdNotify.watchdog?
      end
    end

    it "is true when WATCHDOG_PID matches the current process" do
      with_env("WATCHDOG_USEC" => "1000", "WATCHDOG_PID" => $$.to_s) do
        assert Sidekiq::SdNotify.watchdog?
      end
    end

    it "is false when WATCHDOG_PID is another process" do
      with_env("WATCHDOG_USEC" => "1000", "WATCHDOG_PID" => ($$ + 1).to_s) do
        refute Sidekiq::SdNotify.watchdog?
      end
    end
  end
end
