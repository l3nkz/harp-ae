function human_readable() {
    name=$1
    name=${name//\?/}
    name=${name//\!/}
    name=${name//|/ + }

    echo "$name"
}

function save_name() {
    name=$1
    name=${name//\?/}
    name=${name//\!/}
    name=${name//|/_}

    echo "$name"
}
