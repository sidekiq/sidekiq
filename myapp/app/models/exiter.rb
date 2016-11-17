class Exiter
  def self.run
    Thread.new do
      sleep 0.1
      exit(0)
    end
  end
end
