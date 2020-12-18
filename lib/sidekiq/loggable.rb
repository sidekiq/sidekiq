module Loggable
  attr_accessor :logger

  def info(*args)
    @logger.debug(*args)
  end

  def warn(*args)
    @logger.debug(*args)
  end

  def debug(*args)
    @logger.debug(*args)
  end
end
