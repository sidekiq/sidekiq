.PHONY: build bundle test bash

build:
	docker-compose build

bundle:
	docker-compose run --rm library bundle install

test:
	docker-compose run --rm library bash -c "REDIS_URL=redis://redis:6379/1 bundle exec rake"

bash:
	docker-compose run --rm library bash
