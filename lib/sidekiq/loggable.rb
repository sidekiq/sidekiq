module Loggable
  def info(*args)
    @logger.info(*args)
  end

  def warn(*args)
    @logger.warn(*args)
  end

  def debug(*args)
    @logger.debug(*args)
  end
end
