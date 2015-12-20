# yoshoku
Fusion cooking including CFN Templating engine

## Setup

requires ruby 2.2+

bundle install

```bash
bundle install
```

### Rake tasks
```bash
$ rake -T


rake cfn:generate   # generate cloudformation
rake cfn:deploy     # deploy cloudformation templates to S3
rake cfn:create     # creates an environment
rake cfn:tear_down  # delete/tears down the environment
rake cfn:update     # updates the environment

##Mirror Setup

Use this for end use. Keep this one separate to fork below for contributing.  In the mirror you can pull from the public. If you fork for pull requests you can add a remote based on the private mirror if that suits.

git clone --bare https://github.com/base2Services/yoshoku.git
cd yoshoku.git
git push --mirror https://github.com/<OTHER_NAME>/private_implementation.git
cd ..
rm -rf yoshoku.git

git clone https://github.com/<OTHER_NAME>/private_implementation.git
cd private_implementation
git remote add yoshoku-public https://github.com/base2Services/yoshoku.git

## Developer Setup

### Tools setup (Mac OSX)

* Install [homebrew](http://brew.sh)

* Install git-flow

    brew install git-flow

* Install github CLI

    brew install hub

### Workspace Setup

1. Fork this repo into your own github account

2. Clone your fork into your local Workspace

        git clone git@github.com:<username>/yoshoku.git

3. Add Upstream Remote

        git remote add upstream git@github.com:base2Services/yoshoku.git

4. Initialise git-flow

        git flow init -d

5. Update branch tracking to point to upstream repo

        git checkout develop
        git branch --set-upstream-to=upstream/master
        git checkout master
        git branch --set-upstream-to=upstream/master

