Sidekiq
==============

  - [![Gem Version](https://badge.fury.io/rb/sidekiq.png)](https://rubygems.org/gems/sidekiq)
  - [![Code Climate](https://codeclimate.com/github/mperham/sidekiq.png)](https://codeclimate.com/github/mperham/sidekiq)
  - [![Build Status](https://travis-ci.org/mperham/sidekiq.png)](https://travis-ci.org/mperham/sidekiq)
  - [![Coverage Status](https://coveralls.io/repos/mperham/sidekiq/badge.png?branch=master)](https://coveralls.io/r/mperham/sidekiq)


Ruby用のシンプルで効率的なメッセージ処理ライブラリ

Sidekiqはスレッドを使用して、同じプロセス内で多数のメッセージを同時に処理します。
Railsは必須ではありませんが、Rails 3と緊密に統合してバックグラウンドメッセージ処理を
非常にシンプルにすることができます。

SidekiqはResqueと互換性があります。Resqueと全く同じメッセージフォーマットを使用するため、
既存のResque処理ファームに統合することができます。SidekiqとResqueを同時に並行して実行し、
ResqueクライアントでRedisにメッセージをエンキューしてSidekiqで処理することができます。

同時に、Sidekiqはマルチスレッディングを使用するため、Resque（ジョブごとに新しいプロセスを
フォークする）よりもメモリ効率が大幅に優れています。CPUを100%使用するためには50個の200MBの
Resqueプロセスが必要なところ、1個の300MBのSidekiqプロセスで同じCPUを100%使用し、
同じ量の作業を実行できます。[Resqueのメモリ効率に関する私のブログ投稿](http://blog.carbonfive.com/2011/09/16/improving-resques-memory-efficiency/)
と、Carbon Fiveクライアントのresque処理ファームを9台のマシンから1台のマシンに縮小できた方法をご覧ください。


必要要件
-----------------

Ruby 1.9.3およびJRuby 1.6.x（1.9モード）でテストしています。他のバージョン/VMは
未テストですが、できる限りサポートします。Ruby 1.8はサポートされていません。

Redis 2.0以上が必要です。


インストール
-----------------

    gem install sidekiq


はじめ方
-----------------

シンプルな3ステップのプロセスについては、[sidekiqホームページ](http://mperham.github.com/sidekiq)をご覧ください。
[Railscast #366](http://railscasts.com/episodes/366-sidekiq)を視聴して、Sidekiqの動作を確認できます。すべてが正しく設定されていれば、次のように表示されます：

![Web UI](https://github.com/mperham/sidekiq/raw/master/examples/web-ui.png)



詳細情報
-----------------

詳細については、[sidekiq wiki](https://github.com/mperham/sidekiq/wiki)をご覧ください。
[irc.freenode.netの#sidekiq](irc://irc.freenode.net/#sidekiq)はこのプロジェクト専用ですが、
バグレポートや機能リクエストの提案は[Githubのissues](https://github.com/mperham/sidekiq/issues)を通じて行ってください。

[Librelist](http://librelist.org)経由のメーリングリストもあり、<sidekiq@librelist.org>に
本文に挨拶を含めたメールを送信することで購読できます。購読解除するには、
<sidekiq-unsubscribe@librelist.org>にメールを送信するだけです。
アーカイブが開始されたら、[アーカイブ](http://librelist.com/browser/sidekiq/)にアクセスして過去のスレッドを確認できます。


問題が発生した場合
-----------------

**質問や問題について、Sidekiqのコミッターに直接メールを送らないでください。** コミュニティは公開の場で議論が行われるときに最もよく機能します。

問題が発生した場合は、[FAQ](https://github.com/mperham/sidekiq/wiki/FAQ)と[トラブルシューティング](https://github.com/mperham/sidekiq/wiki/Problems-and-Troubleshooting)のwikiページを確認してください。問題についてissuesを検索するのも良いアイデアです。それでも解決しない場合は、Sidekiqメーリングリストにメールを送信するか、新しいissueを開いてください。
メーリングリストは使用方法に関する質問をするのに最適な場所です。バグだと思われる問題に遭遇した場合は、issueを開いてください。


ライセンス
-----------------

ライセンスの詳細については、LICENSEを参照してください。


著者
-----------------

Mike Perham, [@mperham](https://twitter.com/mperham), [http://mikeperham.com](http://mikeperham.comkakuni)
