#!/usr/bin/env bash
# Borg backup script for {{ item.name }}

source b-log.sh

LOG_LEVEL_INFO

log_or_exit() {
  operation=$1
  return_code=$2

  case $return_code in
  0)
    INFO $operation "successful"
    ;;
  *)
    ERROR $operation "ended with error code $return_code"
    exit $return_code
    ;;
  esac
}

# Use 'sem' in order to make sure that only one instance of borg runs at
# a given instant
BORG="sem --jobs 1 --semaphoretimeout -{{ borg_sem_wait_time }} --id borg borg"

# Setting this, so the repo does not need to be given on the commandline:
export BORG_REPO={{ borg_repository }}

# Set prefix to use for the borg archive
PREFIX={{ ansible_hostname }}_{{ item.name }}

trap 'echo [$LOG_TAG] $( date ) Backup interrupted >&2; exit 2' INT TERM

backup_{{ item.name }}()
{
    INFO "Starting backup"

    {% if item.pre_script %}
        INFO "Calling pre hook script"

        ./{{ item.name }}_pre.sh
        prehook_exit=$?
        log_or_exit "Pre hook" $prehook_exit
    {% endif %}

    # Backup the most important directories into an archive named after
    # the machine this script is currently running on:
    $BORG create                              \
    {% if item.exclude %}
        --exclude {{  item.exclude | default([]) | join(" --exclude ") }} \
    {% endif %}
        ::$PREFIX'_{now:%Y-%m-%d_%H:%M:%S}'   \
        {{ item.paths | join(" ") }}

    backup_exit=$?
    log_or_exit "Backup" $backup_exit

    INFO "Pruning repository"

    # Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
    # archives of THIS machine. The '{hostname}-' prefix is very important to
    # limit prune's operation to this machine's archives and not apply to
    # other machines' archives also:

    $BORG prune --prefix $PREFIX
    {%- if item.prune.minutely %} --keep-minutely {{ item.prune.minutely }}{% endif %}
    {%- if item.prune.hourly %} --keep-hourly {{ item.prune.hourly }}{% endif %}
    {%- if item.prune.daily %} --keep-daily {{ item.prune.daily }}{% endif %}
    {%- if item.prune.weekly %} --keep-weekly {{ item.prune.weekly }}{% endif %}
    {%- if item.prune.monthly %} --keep-monthly {{ item.prune.monthly }}{% endif %}
    {%- if item.prune.yearly %} --keep-weekly {{ item.prune.yearly }}{% endif %}

    prune_exit=$?
    log_or_exit "Pruning" $prune_exit

    {% if item.post_script %}
        INFO "Calling post hook script"

        ./{{ item.name }}_post.sh
        post_hook_exit=$?
        log_or_exit "Post hook" $post_hook_exit
    {% endif %}

    INFO "Exiting normally"
}

backup_{{ item.name }}
exit 0