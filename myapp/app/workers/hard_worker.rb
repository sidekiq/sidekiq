class HardWorker
  def perform(name, count)
    print "#{Thread.current} Working hard\n"
    sleep 3
  end
end
