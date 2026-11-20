#!/usr/bin/env bash
set -euo pipefail

image=${1:-qdevice-witness:0.1.0}
scratch=$(mktemp -d)
name="qdevice-smoke-$$"
state="$name-state"
restored="$name-restored"

cleanup() {
    if [[ $1 != 0 ]]; then
        docker logs "$name" >&2 || true
    fi
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker volume rm "$state" "$restored" >/dev/null 2>&1 || true
    rm -rf -- "$scratch"
}
trap 'cleanup "$?"' EXIT

write_options() {
    docker run --platform linux/amd64 --rm -i -v "$state:/data" --entrypoint /bin/sh \
        "$image" -c 'cat > /data/options.json'
}

start_witness() {
    docker run --platform linux/amd64 -d --name "$name" -v "$1:/data" \
        -p 127.0.0.1::5403 -p 127.0.0.1::22 "$image" >/dev/null
    for _ in {1..30}; do
        if docker exec "$name" corosync-qnetd-tool -s > "$scratch/status" 2>/dev/null; then
            grep -qi 'TLS:.*Required (client certificate required)' "$scratch/status"
            return
        fi
        sleep 1
    done
    return 1
}

stop_witness() {
    docker stop "$name" >/dev/null
    docker rm "$name" >/dev/null
}

ca_fingerprint() {
    docker exec "$name" openssl x509 -in /etc/corosync/qnetd/nssdb/qnetd-cacert.crt \
        -noout -fingerprint -sha256
}

docker volume create "$state" >/dev/null
docker volume create "$restored" >/dev/null
printf '{}\n' | write_options
start_witness "$state"
docker exec "$name" ps -o user:16,comm -C corosync-qnetd | grep -q '^coroqnetd '
docker exec "$name" test ! -e /etc/services.d/enrollment-ssh
fingerprint=$(ca_fingerprint)
stop_witness

ssh-keygen -q -t rsa -b 2048 -N '' -C smoke-test -f "$scratch/id_rsa"
ssh-keygen -q -t ed25519 -N '' -f "$scratch/unrelated"
printf '{"ssh_public_key":"%s"}\n' "$(<"$scratch/id_rsa.pub")" | write_options
start_witness "$state"
[[ $(ca_fingerprint) == "$fingerprint" ]]

port=$(docker port "$name" 22/tcp)
port=${port##*:}
host_key=$(docker exec "$name" cat /data/ssh/ssh_host_ed25519_key.pub)
printf '[127.0.0.1]:%s %s\n' "$port" "$host_key" > "$scratch/known_hosts"
cat > "$scratch/ssh_config" <<EOF
Host 127.0.0.1
    Port $port
    User root
    UserKnownHostsFile $scratch/known_hosts
    StrictHostKeyChecking yes
    BatchMode yes
    IdentitiesOnly yes
    ConnectTimeout 3
EOF
ssh -F "$scratch/ssh_config" -i "$scratch/id_rsa" 127.0.0.1 true
docker cp "$scratch/id_rsa" "$name:/tmp/id_rsa"
docker cp "$scratch/id_rsa.pub" "$name:/tmp/id_rsa.pub"
docker exec "$name" sh -ec '
    printf "127.0.0.1 %s\n" "$(cat /data/ssh/ssh_host_ed25519_key.pub)" > /tmp/known_hosts
    ssh-copy-id -i /tmp/id_rsa -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile=/tmp/known_hosts root@127.0.0.1
    rm /tmp/id_rsa /tmp/id_rsa.pub /tmp/known_hosts
'
if ssh -F "$scratch/ssh_config" -i "$scratch/unrelated" 127.0.0.1 true; then
    printf '%s\n' 'Enrollment SSH accepted an unrelated key.' >&2
    exit 1
fi

scp -F "$scratch/ssh_config" -i "$scratch/id_rsa" \
    '127.0.0.1:/etc/corosync/qnetd/nssdb/qnetd-cacert.crt' "$scratch/ca.crt"
openssl req -new -newkey rsa:2048 -nodes -subj /CN=smoke-test -outform DER \
    -keyout "$scratch/cluster.key" -out "$scratch/cluster.crq" 2>/dev/null
scp -F "$scratch/ssh_config" -i "$scratch/id_rsa" "$scratch/cluster.crq" '127.0.0.1:/tmp/cluster.crq'
ssh -F "$scratch/ssh_config" -i "$scratch/id_rsa" 127.0.0.1 \
    corosync-qnetd-certutil -s -c /tmp/cluster.crq -n smoke-test
scp -F "$scratch/ssh_config" -i "$scratch/id_rsa" \
    '127.0.0.1:/etc/corosync/qnetd/nssdb/cluster-smoke-test.crt' "$scratch/cluster.crt"
openssl x509 -inform DER -in "$scratch/cluster.crt" -out "$scratch/cluster.pem"
openssl verify -CAfile "$scratch/ca.crt" "$scratch/cluster.pem"
stop_witness

# A malformed key must leave QNetd available and must not start SSH.
printf '{"ssh_public_key":"ssh-rsa invalid"}\n' | write_options
start_witness "$state"
docker exec "$name" test ! -e /etc/services.d/enrollment-ssh
stop_witness

printf '{}\n' | write_options
docker run --platform linux/amd64 --rm -v "$state:/source:ro" -v "$restored:/restored" \
    --entrypoint /bin/sh "$image" -c 'tar -C /source -cf - . | tar -C /restored -xf -'
start_witness "$restored"
[[ $(ca_fingerprint) == "$fingerprint" ]]
docker exec "$name" test ! -e /etc/services.d/enrollment-ssh
stop_witness

# Leave a damaged database in place for recovery, rather than replacing the CA.
docker run --platform linux/amd64 --rm -v "$restored:/data" --entrypoint /bin/sh \
    "$image" -c 'rm /data/qnetd/nssdb/key4.db'
docker run --platform linux/amd64 -d --name "$name" -v "$restored:/data" "$image" >/dev/null
for _ in {1..20}; do
    [[ $(docker inspect -f '{{.State.Status}}' "$name") != running ]] && break
    sleep 1
done
[[ $(docker inspect -f '{{.State.Status}}' "$name") == exited ]]
docker logs "$name" 2>&1 | grep 'QNetd certificate state is incomplete' >/dev/null
docker run --platform linux/amd64 --rm -v "$restored:/data:ro" --entrypoint /bin/sh \
    "$image" -c 'test ! -e /data/qnetd/nssdb/key4.db'

printf '%s\n' 'QNetd container lifecycle and enrollment checks passed.'
