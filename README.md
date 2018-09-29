# Gitlab Reporting

Reporting across groups on gitlab is not possible out of the box.

Using the API the information can be gathered (collected) and processed (reported).

Makes use of:
- python-gitlab: https://github.com/python-gitlab/python-gitlab
- jq

The Gitlab API is access via the `python-gitlab` CLI, the logic is done in bash (just because we can).

## Steps

A simple Makefile is provided:
- `make build`: builds the docker container with all required tooling
- `make collect`: retrieves the api data and stores in on disk
- `make report`: processes the stored data and generates all the reports
- `make gitlab`: to save some typing when wanting to run some manual lookup

### Collecting

Assuming you want to use the hosted github.com and using an access token (other options are possible):
`export GITLAB_API_PRIVATE_TOKEN=<your token here>`

`make collect GITLAB_ROOT_IDS="id1 id2"`

The ROOT_IDS are the ids of the root groups you want to inspect.

A group id can be found via `make gitlab CMD="group list --all-available yes --search gitlab-com"` if you're looking for https://gitlab.com/gitlab-com


It will walk the given groups and collect all underlying groups, the members of those groups and the projects.
This could take some time to complete.

### Reporting

After the data is collected, reporting can be done `make report`.

## Available reports

### Access rights

Currently expire date is not taken into account

#### access_per_group.md

Only the members that are explicitly added to the group (no inheritance)

Per group:
| name | owner | maintainer | developer | reporter | guest
| ---- | :---: | :--------: | :-------: | :------: | :---:
| Full name 1 |  owner |   |   |   |   
| Full name 2  |    |   | developer |   |   

And if projects sare hared with this group
| project | role limited to
| -- | --
| project x | developer

#### access_per_group-full.md

Like access per group, but also shown inherited users from groups above

| name | owner | maintainer | developer | reporter | guest
| ---- | :---: | :--------: | :-------: | :------: | :---:
| Full name 1 |  owner |   |   |   |   
| Full name 2  |    |   | developer |   |   
| _^ Full name 3_ | | | _developer_ | |

#### access_per_user.md

Only groups where the user is explicitly added

Per user (fullname + userid)

| name | owner | maintainer | developer | reporter | guest
| ---- | :---: | :--------: | :-------: | :------: | :---:
| gitlab-com/*  |  owner |   |   |   |   
