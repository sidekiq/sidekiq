module Myapp
  class Current < ActiveSupport::CurrentAttributes
    attribute :tenant_id
  end
end
