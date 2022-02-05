.PHONY: build bundle test bash

build:
	docker-compose build

bundle:
	docker-compose run --rm library bundle install

test:
	docker-compose run --rm library bundle exec rake

bash:
	docker-compose run --rm library bash
