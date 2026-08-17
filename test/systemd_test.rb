# frozen_string_literal: true

require_relative "helper"
require "sidekiq/sd_notify"
require "sidekiq/systemd"

describe "Systemd" do
  before do
    ::Dir::Tmpname.create("sidekiq_socket") do |sockaddr|
      @sockaddr = sockaddr
      @socket = Socket.new(:UNIX, :DGRAM, 0)
      socket_ai = Addrinfo.unix(sockaddr)
      @socket.bind(socket_ai)
      ENV["NOTIFY_SOCKET"] = sockaddr
    end
  end

  after do
    @socket&.close
    File.unlink(@sockaddr) if @sockaddr
    @socket = nil
    @sockaddr = nil
  end

  def socket_message
    @socket.recvfrom(50)[0]
  end

  it "notifies" do
    count = Sidekiq::SdNotify.ready
    assert_equal(socket_message, "READY=1")
    assert_equal(ENV["NOTIFY_SOCKET"], @sockaddr)
    assert_equal(count, 7)

    count = Sidekiq::SdNotify.stopping
    assert_equal(socket_message, "STOPPING=1")
    assert_equal(ENV["NOTIFY_SOCKET"], @sockaddr)
    assert_equal(count, 10)

    refute Sidekiq::SdNotify.watchdog?
  end

  it "sends the reloading payload" do
    Sidekiq::SdNotify.reloading
    assert_equal "RELOADING=1", socket_message
  end

  it "sends a custom status payload" do
    Sidekiq::SdNotify.status("doing work")
    assert_equal "STATUS=doing work", socket_message
  end

  it "sends an errno payload" do
    Sidekiq::SdNotify.errno(3)
    assert_equal "ERRNO=3", socket_message
  end

  it "sends the main pid payload" do
    Sidekiq::SdNotify.mainpid(123)
    assert_equal "MAINPID=123", socket_message
  end

  it "sends the fdstore payload" do
    Sidekiq::SdNotify.fdstore
    assert_equal "FDSTORE=1", socket_message
  end

  it "removes NOTIFY_SOCKET from the env when unset_env is true" do
    Sidekiq::SdNotify.ready(true)
    assert_nil ENV["NOTIFY_SOCKET"]
  end

  it "keeps NOTIFY_SOCKET in the env by default" do
    Sidekiq::SdNotify.ready
    assert_equal @sockaddr, ENV["NOTIFY_SOCKET"]
  end

  it "raises NotifyError when the socket cannot be reached" do
    ENV["NOTIFY_SOCKET"] = "/nonexistent/sidekiq/missing.sock"
    assert_raises(Sidekiq::SdNotify::NotifyError) do
      Sidekiq::SdNotify.notify("READY=1")
    end
  end
end

describe "Sidekiq::SdNotify without systemd" do
  def restore_env(key, value)
    value.nil? ? ENV.delete(key) : (ENV[key] = value)
  end

  before do
    @orig = ENV.values_at("NOTIFY_SOCKET", "WATCHDOG_USEC", "WATCHDOG_PID")
    ENV.delete("NOTIFY_SOCKET")
    ENV.delete("WATCHDOG_USEC")
    ENV.delete("WATCHDOG_PID")
  end

  after do
    restore_env("NOTIFY_SOCKET", @orig[0])
    restore_env("WATCHDOG_USEC", @orig[1])
    restore_env("WATCHDOG_PID", @orig[2])
  end

  it "returns nil from notify when NOTIFY_SOCKET is unset" do
    assert_nil Sidekiq::SdNotify.notify("READY=1")
  end

  it "returns nil from the convenience helpers with no socket" do
    assert_nil Sidekiq::SdNotify.ready
    assert_nil Sidekiq::SdNotify.stopping
  end

  describe "watchdog?" do
    it "is false when WATCHDOG_USEC is unset" do
      refute Sidekiq::SdNotify.watchdog?
    end

    it "is false when WATCHDOG_USEC is not an integer" do
      ENV["WATCHDOG_USEC"] = "abc"
      refute Sidekiq::SdNotify.watchdog?
    end

    it "is false when WATCHDOG_USEC is zero or negative" do
      ENV["WATCHDOG_USEC"] = "0"
      refute Sidekiq::SdNotify.watchdog?
      ENV["WATCHDOG_USEC"] = "-5"
      refute Sidekiq::SdNotify.watchdog?
    end

    it "is true for a valid usec when WATCHDOG_PID is unset" do
      ENV["WATCHDOG_USEC"] = "100"
      assert Sidekiq::SdNotify.watchdog?
    end

    it "is true when WATCHDOG_PID matches the current process" do
      ENV["WATCHDOG_USEC"] = "100"
      ENV["WATCHDOG_PID"] = $$.to_s
      assert Sidekiq::SdNotify.watchdog?
    end

    it "is false when WATCHDOG_PID is another process" do
      ENV["WATCHDOG_USEC"] = "100"
      ENV["WATCHDOG_PID"] = ($$ + 1).to_s
      refute Sidekiq::SdNotify.watchdog?
    end
  end
end
