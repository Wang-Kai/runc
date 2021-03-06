#!/usr/bin/env bats

load helpers

function setup() {
  teardown_busybox
  setup_busybox
}

function teardown() {
  teardown_busybox
}

@test "events --stats" {
  # XXX: currently cgroups require root containers.
  requires root
  init_cgroup_paths

  # run busybox detached
  runc run -d --console-socket "$CONSOLE_SOCKET" test_busybox
  [ "$status" -eq 0 ]

  # generate stats
  runc events --stats test_busybox
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == [\{]"\"type\""[:]"\"stats\""[,]"\"id\""[:]"\"test_busybox\""[,]* ]]
  [[ "${lines[0]}" == *"data"* ]]
}

@test "events --interval default" {
  # XXX: currently cgroups require root containers.
  requires root
  init_cgroup_paths

  # run busybox detached
  runc run -d --console-socket "$CONSOLE_SOCKET" test_busybox
  [ "$status" -eq 0 ]

  # spawn two sub processes (shells)
  # the first sub process is an event logger that sends stats events to events.log
  # the second sub process waits for an event that includes test_busybox then
  # kills the test_busybox container which causes the event logger to exit
  (__runc events test_busybox > events.log) &
  (
    retry 10 1 eval "grep -q 'test_busybox' events.log"
    teardown_running_container test_busybox
  ) &
  wait # wait for the above sub shells to finish

  [ -e events.log ]

  run cat events.log
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == [\{]"\"type\""[:]"\"stats\""[,]"\"id\""[:]"\"test_busybox\""[,]* ]]
  [[ "${lines[0]}" == *"data"* ]]
}

@test "events --interval 1s" {
  # XXX: currently cgroups require root containers.
  requires root
  init_cgroup_paths

  # run busybox detached
  runc run -d --console-socket "$CONSOLE_SOCKET" test_busybox
  [ "$status" -eq 0 ]

  # spawn two sub processes (shells)
  # the first sub process is an event logger that sends stats events to events.log once a second
  # the second sub process tries 3 times for an event that incudes test_busybox
  # pausing 1s between each attempt then kills the test_busybox container which
  # causes the event logger to exit
  (__runc events --interval 1s test_busybox > events.log) &
  (
    retry 3 1 eval "grep -q 'test_busybox' events.log"
    teardown_running_container test_busybox
  ) &
  wait # wait for the above sub shells to finish

  [ -e events.log ]

  run eval "grep -q 'test_busybox' events.log"
  [ "$status" -eq 0 ]
}

@test "events --interval 100ms" {
  # XXX: currently cgroups require root containers.
  requires root
  init_cgroup_paths

  # run busybox detached
  runc run -d --console-socket "$CONSOLE_SOCKET" test_busybox
  [ "$status" -eq 0 ]

  #prove there is no carry over of events.log from a prior test
  [ ! -e events.log ]

  # spawn two sub processes (shells)
  # the first sub process is an event logger that sends stats events to events.log once every 100ms
  # the second sub process tries 3 times for an event that incudes test_busybox
  # pausing 100s between each attempt then kills the test_busybox container which
  # causes the event logger to exit
  (__runc events --interval 100ms test_busybox > events.log) &
  (
    retry 3 0.100 eval "grep -q 'test_busybox' events.log"
    teardown_running_container test_busybox
  ) &
  wait # wait for the above sub shells to finish

  [ -e events.log ]

  run eval "grep -q 'test_busybox' events.log"
  [ "$status" -eq 0 ]
}

@test "events oom" {
  # XXX: currently cgroups require root containers.
  requires root cgroups_swap
  init_cgroup_paths

  # we need the container to hit OOM, so disable swap
  update_config '(.. | select(.resources? != null)) .resources.memory |= {"limit": 33554432, "swap": 33554432}' "${BUSYBOX_BUNDLE}"

  # run busybox detached
  runc run -d --console-socket "$CONSOLE_SOCKET" test_busybox
  [ "$status" -eq 0 ]

  # spawn two sub processes (shells)
  # the first sub process is an event logger that sends stats events to events.log
  # the second sub process exec a memory hog process to cause a oom condition
  # and waits for an oom event
  (__runc events test_busybox > events.log) &
  (
    retry 10 1 eval "grep -q 'test_busybox' events.log"
    # shellcheck disable=SC2016
    __runc exec -d test_busybox sh -c 'test=$(dd if=/dev/urandom ibs=5120k)'
    retry 10 1 eval "grep -q 'oom' events.log"
    __runc delete -f test_busybox
  ) &
  wait # wait for the above sub shells to finish

  grep -q '{"type":"oom","id":"test_busybox"}' events.log
}
