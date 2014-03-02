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
      puts <<-BANNER
                      L      i          L     ;f
    .,          LLL.  L      i          L     ,l            GGGGG
 ,G  @       G L   .         i          L                   G   Gf
 @@  @   ,@@;  L      L   LLLf   iLLL   L  lL  ;  iLLLL     G . GG G;GG fGGGG
 .@@@f .@@@    L      L  L   i   L   L  L  L   ;  L   L     G   GG GG   G   G
 @@@@L@@@       LLL.  L. L   i  i    L  L L    ;  L   L     G   G: G;   G   G,
 @@@@@@L           L  L  L   i  fLLLLL  LLf    ;  L   L     GGGGG  G;   G   G;
C@  @@@            L  L  L . i. :,      L L:   ;  L   L     G      G;   G   G.
C    @l            L  L  L   L   L      L  L   ;  L   L     G.     G;   G   G
     @.        lLLL   L   LLt t  ,LLL.  L   L  ;   LL L     G      G;    GGGt
    .@                                              . L.
   ..@                                                L
    .@
    @
BANNER
    end
  end
end
