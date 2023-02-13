# Contributing

## Issues

When opening an issue:

* include the full **backtrace** with your error
* include your Sidekiq initializer
* list versions you are using: Ruby, Rails, Sidekiq, OS, etc.

It's always better to include more info rather than less.

## Code

It's always best to open an issue before investing a lot of time into a
fix or new functionality.  Functionality must meet my design goals and
vision for the project to be accepted; I would be happy to discuss how
your idea can best fit into Sidekiq.

### Local development setup

You need Redis installed and a Ruby version that fulfills the requirements in
`sidekiq.gemspec`. Then:

```
bundle install
```

And in order to run the tests and linter checks:

```
bundle exec rake
```

### Beginner's Guide to Local Development Setup

#### 1. Fork [sidekiq/sidekiq](https://github.com/sidekiq/sidekiq) project repository to your personal GitHub account

#### 2. Click 'Clone or Download' button in personal sidekiq repository and copy HTTPS URL

#### 3. On local machine, clone repository

```
git clone HTTPS-URL-FOR-PERSONAL-SIDEKIQ-REPOSITORY
```

#### 4. Navigate to your local machine's sidekiq directory

```
cd sidekiq/
```

#### 5. Set remote upstream branch

```
git remote add upstream https://github.com/sidekiq/sidekiq.git
```

#### 6. Install necessary gems for development and start Redis server

```
bundle install
```

```
redis-server
```

#### 7. Navigate to myapp (small Rails app inside Sidekiq repository used for development)

```
cd myapp/
```

#### 8. Run required migration in order to launch Rails app

```
rake db:migrate
```

#### 9. Launch Rails app

```
rails s
```

#### 10. Create feature branch and start contributing!

```
git checkout -b new_feature_name
```

### 11. Keep your forked branch up to date with changes in main repo
```
git pull upstream main
```

## Legal

By submitting a Pull Request, you disavow any rights or claims to any changes
submitted to the Sidekiq project and assign the copyright of
those changes to Contributed Systems LLC.

If you cannot or do not want to reassign those rights (your employment
contract for your employer may not allow this), you should not submit a PR.
Open an issue and someone else can do the work.

This is a legal way of saying "If you submit a PR to us, that code becomes ours".
99.9% of the time that's what you intend anyways; we hope it doesn't scare you
away from contributing.
