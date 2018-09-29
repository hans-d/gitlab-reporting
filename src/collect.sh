#!/bin/bash

set -e

ROOT_IDS=${ROOT_IDS:-$@}
JSON_FOLDER=${JSON_FOLDER:-"./json"}

mkdir -p ${JSON_FOLDER}

if [ -z "${ROOT_IDS}" ]; then
    echo "specify your root group(s) as parameters"
    exit 1
fi


function log {
    if [ $NO_LOG ]; then
        return
    fi
    echo "$@"
}

function gitlab_group {
    local GROUP_ID=$1
    gitlab -o json group get --id ${GROUP_ID}
}

function gitlab_group_members {
    local GROUP_ID=$1
    gitlab -o json group-member list --group-id  ${GROUP_ID}  | jq --arg id $GROUP_ID '. | map( . + {group_id: $id} )'
}

function gitlab_all_group_members {
    # output from gitlab is very raw, and needs some processing
    # - users can appear multiple times (also with same access level)
    # - need to keep the ones withe highest access level
    # - not taken expires_at into account
    local GROUP_ID=$1
    # not yet available via the current cli: https://github.com/python-gitlab/python-gitlab/pull/599

    gitlab group-member-all list --group-id $id

    #local data=$(gitlab -o json group-member-all --group-id ${GROUP_ID} | jq --arg id $GROUP_ID '. | map( . + {group_id: $id} )')

    echo "$data" | jq 'group_by( .id)[] |
    { 
        access_level: [.[].access_level] | max ,
        avatar_url: .[0].avatar_url,
        id: .[0].id,
        name: .[0].name,
        state: .[0].state,
        username: .[0].username,
        web_url: .[0].web_url,
        group_id: .[0].group_id
    }' | jq -s '.'

}

function gitlab_project_members {
    local PROJECT_ID=$1
    local result=$(gitlab -o json project-member list --project-id ${PROJECT_ID} | jq -c '.')
    
    if  [ "$result" == "{}" ]; then
        echo "[]"
    else
        echo "$result" | jq --arg id $PROJECT_ID '. | map( . + {project_id: $id} )'
    fi
}

function gitlab_subgroups {
    local GROUP_ID=$1
    gitlab -o json group-subgroup list --group-id ${GROUP_ID}
}

function gitlab_all_subgroups {
    local GROUP_IDS=$@

    for group_id in $GROUP_IDS; do
        local subgroups=$(gitlab_subgroups $group_id)

        if [ $ONE_GROUP ]; then
            return
        fi

        if [ "$subgroups" == "null" ]; then
            return
        fi

        echo $subgroups | jq -c '.[]'
        for next in $(echo "${subgroups}" | jq -r '.[].id'); do
            if [ "$next" == "null" ]; then
                continue
            fi

            echo $(gitlab_all_subgroups $next)
        done
    done
}

function collect_all {
    log "collecting for ${ROOT_IDS}:"

    log "... group structure"
    SUBGROUPS_JSON=$(gitlab_all_subgroups ${ROOT_IDS})
    SUBGROUP_IDS=$(echo $SUBGROUPS_JSON | jq '.id')

    log "... group details"
    for group_id in $ROOT_IDS $SUBGROUP_IDS; do
        log "    ... group $group_id"
        GROUP_JSON[$group_id]=$(gitlab_group $group_id)

        log "        ... members"
        GROUP_MEMBER_JSON[$group_id]=$(gitlab_group_members $group_id)

        # currently skipping, as method is not yet available in this cli
        #ALL_GROUP_MEMBER_JSON[$group_id]=$(gitlab_all_group_members $group_id)

        projects=$(echo "${GROUP_JSON[$group_id]}" | jq '.projects[].id' )
        for project_id in $projects; do
           log "        ... project $project_id"
            PROJECT_MEMBER_JSON[$project_id]=$(gitlab_project_members $project_id)
        done

    done
}

function export_all {

    function to_json {
        eval "declare -A local ARRAY="${1#*=}
        local i

        for dummy in 1; do
            for i in "${!ARRAY[@]}"; do
                echo "${ARRAY[$i]}" | jq --arg id $i '{ key: $id, value: . }'
            done 
        done | jq -s '.'
    }

    log "exporting to '${JSON_FOLDER}':"
    log "... groups"
    to_json "$(declare -p GROUP_JSON)" > ${JSON_FOLDER}/gitlab_groups.json
    log "... group members"
    to_json "$(declare -p GROUP_MEMBER_JSON)" > ${JSON_FOLDER}/gitlab_group_members.json
    # currently skipping, as method is not yet available in this cli
    #log "... all group members"
    #to_json "$(declare -p ALL_GROUP_MEMBER_JSON)" > ${JSON_FOLDER}/gitlab_all_group_members.json
    log "... project members"
    to_json "$(declare -p PROJECT_MEMBER_JSON)" > ${JSON_FOLDER}/gitlab_project_members.json
}


log "--- start"
log "    (note: api calls can take some time)"
collect_all
export_all
log "--- done"