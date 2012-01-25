class HardWorker
  def perform(name, count)
    sleep 0.01
    puts 'done'
  end
end
