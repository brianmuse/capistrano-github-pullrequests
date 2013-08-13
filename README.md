capistrano-pullrequests
=======================

Deployments for GitHub pull requests

## Installation

    gem install capistrano-github-pullrequests

Add to `Capfile` or `config/deploy.rb`:

    require 'capistrano-github-pullrequests'
    
## Usage

`:pull_request_number` is now an optional configuration. When set, it will deploy the version of the pull request from `/refs/pull/:number/merge`
