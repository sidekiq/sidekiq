module Sidekiq
  module Banner
    def print_oss_banner
      puts %q{         s
        ss
   sss  sss         ss
   s  sss s   ssss sss   ____  _     _      _    _
   s     sssss ssss     / ___|(_) __| | ___| | _(_) __ _
  s         sss         \___ \| |/ _` |/ _ \ |/ / |/ _` |
  s sssss  s             ___) | | (_| |  __/   <| | (_| |
  ss    s  s            |____/|_|\__,_|\___|_|\_\_|\__, |
  s     s s                                           |_|
        s s
       sss
       sss }
    end

    def print_pro_banner
      puts %q{         s
        ss
   sss  sss         ss
   s  sss s   ssss sss   ____  _     _      _    _         ____
   s     sssss ssss     / ___|(_) __| | ___| | _(_) __ _  |  _ \ _ __ ___
  s         sss         \___ \| |/ _` |/ _ \ |/ / |/ _` | | |_) | '__/ _ \
  s sssss  s             ___) | | (_| |  __/   <| | (_| | |  __/| | | (_) |
  ss    s  s            |____/|_|\__,_|\___|_|\_\_|\__, | |_|   |_|  \___/
  s     s s                                           |_|
        s s
       sss
       sss }
    end
  end
end
