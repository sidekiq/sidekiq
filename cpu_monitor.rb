require 'fiddle'
libc = Fiddle.dlopen(nil)
$sched_getcpu = Fiddle::Function.new(
  libc['sched_getcpu'],
  [],
  Fiddle::TYPE_INT
)

def monitor_process(pid)
  last_cpu = $sched_getcpu.call
  puts "Sidekiq worker starting on CPU #{last_cpu}"

  loop do
    current_cpu = $sched_getcpu.call
    if current_cpu != last_cpu
      puts "[#{Process.pid}] Migrated from CPU #{last_cpu} to CPU #{current_cpu} at #{Time.now}"
      last_cpu = current_cpu
    end
    sleep 0.1
  end
end

monitor_process(Process.pid)
