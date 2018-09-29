#!/bin/bash

set -e

BASE64_DECODE_FLAG="--decode"

if [ -f /etc/alpine-release ]; then 
    BASE64_DECODE_FLAG="-d"
fi

JSON_FOLDER=${JSON_FOLDER:-"./json"}
REPORT_FOLDER='./reports'

mkdir -p ${REPORT_FOLDER}

GROUP_JSON=""

function log {
    if [ $NO_LOG ]; then
        return
    fi
    echo "$@"
}


function translate_access_level {
    local level=$1
    case $level in
    10) echo guest;;
    20) echo reporter;;
    30) echo developer;;
    40) echo maintainer;;
    50) echo owner;;
    *) echo Unknown ${level};;
    esac
}

function report_access_level {

    # "| owner | maintainer | developer | reporter | guest"
    # "| :---: | :--------: | :-------: | :------: | :---:"

    local level=$1
    local prefix=${2:-""}
    local markup=${3:-""}
    local name=$(translate_access_level $level)

    if [ "$prefix" != "" ]; then name="$prefix $name"; fi
    if [ "$markup" != "" ]; then name="${markup}${name}${markup}"; fi

    case $level in
    10) echo "   |   |   |   | $name ";;
    20) echo "   |   |   | $name |   ";;
    30) echo "   |   | $name |   |   ";;
    40) echo "   | $name |   |   |   ";;
    50) echo " $name |   |   |   |   ";;
    *)  echo Unknown ${level};;
    esac
}

function import {
    local FILE_ID=$1

    local FILE="${JSON_FOLDER}/gitlab_${FILE_ID}.json"
    local json

    for row in $(cat $FILE | jq -r '.[] | @base64'); do
        data=$(echo ${row} | base64 ${BASE64_DECODE_FLAG})

        key=$(echo $data | jq -r '.key')
        value=$(echo $data | jq -r '.value')

        json[${key}]=${value}
    done
    echo "$(declare -p json)"
}


function order_groups_by_structure {
    local GROUP_IDS=$@

    function group_groups {
        local MATCH=$1
        local root=()
        local group_id

        for group_id in $GROUP_IDS; do

            parent=$(echo ${GROUP_JSON[$group_id]} | jq -r .parent_id)
            if [ $parent != $MATCH ]; then
                continue
            fi
            local path=$(echo ${GROUP_JSON[$group_id]} | jq -r .full_path)
            root+=("$group_id|$path")
        done

        if [ ${#root[@]} -eq 0 ]; then
            return
        fi

        root=$(echo "${root[*]}" | sed "s/ /\n/g" | sort -t"|" -k2 | cut -d"|" -f 1 )

        local row
        for row in $root; do
            echo $row
            group_groups $row
        done
    }

    echo $(group_groups "null")

}

function report_per_path {

    local FULL=$1
    local row

    echo "# Per path"

    for group_id in $ORDERED_GROUP_IDS; do

        local group_json=${GROUP_JSON[$group_id]}
        local member_json=${GROUP_MEMBER_JSON[$group_id]}
        # cannot use the all group member data currently
        # local all_member_json=${ALL_GROUP_MEMBER_JSON[$group_id]}
        # replacing by computed version
        local parent=$(echo ${group_json} | jq -r '.parent_id' )
        local all_member_json=${COMPUTED_ALL_GROUP_MEMBER_JSON[$parent]}

        local path=$(echo ${group_json} | jq -r '.full_path' )
        echo ""
        echo "## ${path}/* "

        echo ""
        echo "| name | owner | maintainer | developer | reporter | guest"
        echo "| ---- | :---: | :--------: | :-------: | :------: | :---:"


        local member_id
        for member_id in $(sort_user_ids_by_name "${member_json}"); do
            all_member_json=$(echo "${all_member_json}" | jq --argjson id $member_id '.[] | select(.id != $id)' | jq -s '.')
            local data=$(echo "${member_json}" | jq --argjson id $member_id '.[] | select( .id == $id )')
            local name=$(echo $data | jq -r '.name')
            local accesslevel=$(echo $data | jq -r '.access_level')
            local role=$(report_access_level $accesslevel)
            echo "| $name  | $role"
        done

        if [ "$FULL" == "full" ]; then
            for member_id in $(sort_user_ids_by_name "${all_member_json}"); do
                local data=$(echo "${all_member_json}" | jq --argjson id $member_id '.[] | select( .id == $id )')
                local name=$(echo $data | jq -r '.name')
                local accesslevel=$(echo $data | jq -r '.access_level')
                local role=$(report_access_level $accesslevel)
                echo "| ^ _${name}_ | ${role}"
            done
            echo ""

            COMPUTED_ALL_GROUP_MEMBER_JSON[$group_id]=$( echo $( echo "${member_json}" | jq -c .[] ) $( echo "${all_member_json}" | jq -c .[] ) | jq -s '.' )
        fi

        local project_json=$(echo "${group_json}" | jq -r '.shared_projects')
        local project_id
        if [ "$(echo $project_json | jq -c '.[]')" != "" ]; then
            echo "### Projects shared with this group"
            echo "| project | role limited to"
            echo "| -- | --"
            for project_id in $(sort_project_ids_by_path "${project_json}" ); do
                local data=$(echo "${project_json}" | jq --argjson id $project_id '.[] | select( .id == $id )')
                local name=$(echo $data | jq -r '.path_with_namespace')
                local accesslevel=$(echo $data | jq --argjson id $group_id -r '.shared_with_groups[] | select (.group_id == $id) | .group_access_level')
                local role=$(translate_access_level $accesslevel)
                echo "| ${name} | ${role}"
            done
            echo ""
        fi

    done

}

function report_per_user {

    echo "# Per user"

    users=$(echo "${GROUP_MEMBER_JSON[@]}" | jq -c '.[] | { id: .id, name: .name, username: .username }' | jq -sc '. | unique | .[]')

    for member_id in $SORTED_USER_IDS; do

        local member=$(echo $users | jq --argjson id $member_id '. | select (.id == $id) ')
        local name=$(echo $member | jq -r '.name')
        local username=$(echo $member | jq -r '.username')

        echo ""
        echo "## ${name} (${username})"
        echo ""
        echo "| name | owner | maintainer | developer | reporter | guest"
        echo "| ---- | :---: | :--------: | :-------: | :------: | :---:"

        for group_id in $ORDERED_GROUP_IDS; do
            local member_json=${GROUP_MEMBER_JSON[$group_id]}
            local member=$(echo "$member_json" | jq --argjson id $member_id '.[] | select(.id == $id)' )

            local group_json=${GROUP_JSON[$group_id]}
            local path=$(echo ${group_json} | jq -r '.full_path' )

            if [ "$member" != "" ]; then

                local accesslevel=$(echo $member | jq -r '.access_level')
                local role=$(report_access_level $accesslevel)

                echo "| ${path}/*  | $role"
            fi

            local project_type
            for project_type in shared_projects projects; do
                local project_json=$(echo "${group_json}" | jq --arg type ${project_type} -r '.[$type]')
                local project_id

                if [ "$(echo $project_json | jq -c '.[]')" == "" ]; then
                    continue
                fi
                
                for project_id in $(sort_project_ids_by_path "${project_json}" ); do
                    local data=$(echo "${project_json}" | jq --argjson id $project_id '.[] | select( .id == $id )')
                    local name=$(echo $data | jq -r '.path_with_namespace')

                    if [ "$project_type" == "shared_projects" ]; then
                        local accesslevel2=$(echo $data | jq --argjson id $group_id -r '.shared_with_groups[] | select (.group_id == $id) | .group_access_level')

                        if [ ${accesslevel2} -gt ${accesslevel} ]; then
                            accesslevel2=${accesslevel}
                        fi
                        local role=$(report_access_level $accesslevel2)
                        echo "| +-> _${name}_ | ${role}"
                    fi

                    if [ "$project_type" == "projects" ]; then

                        local pmember_json=${PROJECT_MEMBER_JSON[$project_id]}
                        local pmember=$(echo "$pmember_json" | jq --argjson id $member_id '.[] | select(.id == $id)' )

                        local project_json2=$(echo $project_json | jq --argjson id $project_id '.[] | select(.id == $id)' )
                        local path=$(echo ${project_json2} | jq -r '.path_with_namespace' )

                        if [ "$pmember" != "" ]; then
                            local accesslevel2=$(echo $pmember | jq -r '.access_level')
                            local role=$(report_access_level $accesslevel2)
                            echo "| ${path}  | $role"
                        fi
                    fi


                done

            done

        done

  done
}

function sort_user_ids_by_name {
    local json="$1"
    echo $json | jq -c '.[] | { name: .name, id: .id }' | jq -s  '. | sort_by (.name) | .[].id'
}

function sort_project_ids_by_path {
    local json="$1"
    echo $json | jq -c '.[] | { name: .path, id: .id }' | jq -s  '. | sort_by (.name) | .[].id'
}

log "--- start"

log "loading data"
# does not seem to work when placed in a function
log "  groups"
data=$(import "groups")
eval "declare -a GROUP_JSON="${data#*=}

log "  group_members"
data=$(import "group_members")
eval "declare -a GROUP_MEMBER_JSON="${data#*=}

# currently skipping, as method is not yet available in the cli - doing manual compute (see above)
#data=$(import "all_group_members")
#eval "declare -a ALL_GROUP_MEMBER_JSON="${data#*=}

log "  computing group_members_all"
declare -a COMPUTED_ALL_GROUP_MEMBER_JSON
for id in $ROOT_IDS; do
    COMPUTED_ALL_GROUP_MEMBER_JSON[$id]="[]"
done

log "  project_members"
data=$(import "project_members")
eval "declare -a PROJECT_MEMBER_JSON="${data#*=}

log "preprocessing data"
log "  ordered group ids"
ORDERED_GROUP_IDS="$(order_groups_by_structure "${!GROUP_JSON[@]}")"
log "  sorted user ids"
SORTED_USER_IDS=$(echo "${GROUP_MEMBER_JSON[@]}" | jq -c '.[] | { id: .id, name: .name }' | jq -sc '. | unique |sort_by(.name) | .[].id')

log "reporting"
log "  access per path"
report_per_path > $REPORT_FOLDER/access_per_group.md
log "  access per path (full)"
report_per_path "full" > $REPORT_FOLDER/access_per_group-full.md
log "  access per user"
report_per_user > $REPORT_FOLDER/access_per_user.md
log "--- done"