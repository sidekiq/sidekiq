# Sidekiq's software development lifecycle

## 1. Introduction

This document outlines the Software Development Lifecycle (SDLC) process for Sidekiq and its related commercial siblings, Sidekiq Pro and Sidekiq Enterprise.
This documents how we provide a clear, repeatable, and transparent process for all contributors in order to maintain Sidekiq's high-quality, secure, and maintainable codebase. 

## 2. Guiding principles

* Open and transparent: All discussion is done publicly.
* Community-oriented: The community always has an opportunity to give feedback.
* Quality and security-focused: Automated testing and security checks are mandatory for all contributions.
* Convention over configuration: We follow established Ruby idioms and conventions to maximize clarity and minimize overhead. Any defaults should always work for 80% of the users.
* Automate everything: We use GitHub's built-in features to automate checks and reduce manual overhead. 
* Pragmatism: Decisions are always contextual but code should avoid unnecessary complexity if it can depend on conventions.

## 3. Workflow on GitHub

Our workflow is centered around the standard GitHub process of issues, branches, commits, and pull requests.

### Issues

Issues are used to track feature requests, bug reports, and tasks.
Anyone can create an issue.
Contributors should use the provided issue templates for bug reports and feature requests.
Maintainers are expected to review and label new issues, especially if those issues are related to an area they have recently touched or have expertise in.

### Branching

We use a branch-based workflow.
The `main` branch is always the most stable, release-ready version of the code.
All changes should be made on a new, descriptively named branch.

### Commits

Commit messages should be clear, concise and include standard GitHub workflow activation phrases so commits are automatically linked to any related issue.
We recommend using a conventional commit format (e.g., feat: Add new user service, fix: Correct memory leak).

### Pull Requests

To contribute code, a developer must open a pull request.
A PR will not be merged until all automated checks pass and it has been approved by at least one maintainer.
All PRs require a review.
Reviewers should focus on code quality, test coverage, and adherence to security best practices. 

## 4. The development lifecycle

### Phase 1: Planning and requirements

Every significant release (major or minor) should have an associated milestone in GitHub.
Ideas and feature requests are discussed in issues.
The maintainers evaluate and prioritize issues, linking them to a milestone.
The milestone provides a clear roadmap and status for the upcoming release.

### Phase 2: Development and coding

Contributors should create a new branch for their changes.
Changes are committed frequently with clear commit messages. 
Pull request are opened once code is ready for review and public discussion.

### Phase 3: Testing and quality assurance

All code must be accompanied by relevant automated tests.
Code changes must also include testing for a substantial percentage of their code and not reduce the project's overall code coverage.
All code is automatically reformatted when the test suite is run with Bundler.
GitHub Actions automatically runs our test suite, code linters (standard), and security scanners on every push to main.
For new features, contributors and reviewers should perform basic manual testing to ensure functionality. 

### Phase 4: Release and deployment

The project does not use semantic versioning but we take all reasonable measures to ensure that "substantial" breaking changes only occur at major version changes.
Minor changes with potential for breakage can happen at minor version bumps (e.g. internal API refactoring).
Changelog entries are added to `Changes.md`, `Pro-Changes.md` and `Ent-Changes.md` and must explain changes, bug fixes, and new features and point to relevant issues.
New Git tags are created for each release (e.g., `v1.2.3`) when the gem is pushed to the gem server. 
Major releases must also provide migration / upgrade documentation to guide users in any necessary application changes.

### Phase 5: Maintenance and support

New bugs reported in issues are fixed by maintainers or community in new PRs.
When a vulnerability is reported, a maintainer will open a private vulnerability report on GitHub to coordinate a fix before disclosing it publicly.
Please see `SECURITY.md` for specific security policies.

## 5. Adjustments for commercial products

Sidekiq Pro and Sidekiq Enterprise are not Open Source but will follow the same workflow
as above where possible.
Issues should be opened in the `sidekiq/sidekiq` repo to represent any change in commercial functionality and provide a place for public discussion.
The private repositories should only contain the actual code and associated pull requests from those maintainers who have access to the private repos.
Not all Open Source maintainers will have access to the private repos, however maintainers who have shown an interest or expertise in an area of commercial functionality may be granted access.
All commercial changes are reviewed by @mperham unless explicitly delegated.

Customers who have an interest in a change to the commercial functionality should open an issue to propose the change.
If the maintainers are positive on the change, the customer may send a private git patch via email to support@contribsys.com as an example implementation with the understanding that they grant all legal rights to that code to Contributed Systems.

**Sidekiq Enterprise customers with an unlimited license may ask for and be granted read-only access to the private repositories for one GitHub user of their choice as long as their license remains in good standing.**
This access is intended to provide oversight by interested parties that nothing malevolent sneaks into the private codebases and that we make a good faith effort to follow these policies in private also.

## 5. Policy changes

This policy is a living document.
Any changes to our workflow should be proposed and discussed via a GitHub Issue or a pull request, following the same contribution guidelines outlined in this document. 