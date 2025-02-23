#!/usr/bin/env bats
# Copyright 2022-2023 Advanced Micro Devices, Inc.
# Copyright 2023 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../common.bash"
load "${BATS_TEST_DIRNAME}/confidential_common.sh"
load "${BATS_TEST_DIRNAME}/tests_common.sh"

setup() {
	SUPPORTED_TEE_HYPERVISORS=("qemu-sev" "qemu-snp" "qemu-tdx" "qemu-se")
	SUPPORTED_NON_TEE_HYPERVISORS=("qemu")

	# This check must be done with "<SPACE>${KATA_HYPERVISOR}<SPACE>" to avoid
	# having substrings, like qemu, being matched with qemu-$something.
	if ! [[ " ${SUPPORTED_TEE_HYPERVISORS[@]} " =~ " ${KATA_HYPERVISOR} " ]] && ! [[ " ${SUPPORTED_NON_TEE_HYPERVISORS} " =~ " ${KATA_HYPERVISOR} " ]]; then
		skip "Test not supported for ${KATA_HYPERVISOR}."
	fi

	if [[ " ${SUPPORTED_NON_TEE_HYPERVISORS} " =~ " ${KATA_HYPERVISOR} " ]]; then
		info "Need to apply image annotations"
	else
		get_pod_config_dir
		setup_unencrypted_confidential_pod
	fi
}

@test "Test unencrypted confidential container launch success and verify that we are running in a secure enclave." {
	[[ " ${SUPPORTED_NON_TEE_HYPERVISORS} " =~ " ${KATA_HYPERVISOR} " ]] && skip "Test not supported for ${KATA_HYPERVISOR}."
	# Start the service/deployment/pod
	kubectl apply -f "${pod_config_dir}/pod-confidential-unencrypted.yaml"

	# Retrieve pod name, wait for it to come up, retrieve pod ip
	pod_name=$(kubectl get pod -o wide | grep "confidential-unencrypted" | awk '{print $1;}')

	# Check pod creation
	kubectl wait --for=condition=Ready --timeout=$timeout pod "${pod_name}"

	coco_enabled=""
	for i in {1..6}; do
		if ! pod_ip=$(kubectl get pod -o wide | grep "confidential-unencrypted" | awk '{print $6;}'); then
			warn "Failed to get pod IP address."
		else
			info "Pod IP address: ${pod_ip}"
			coco_enabled=$(ssh -i ${SSH_KEY_FILE} -o "StrictHostKeyChecking no" -o "PasswordAuthentication=no" root@${pod_ip} "$(get_remote_command_per_hypervisor)" 2> /dev/null) && break
			warn "Failed to connect to pod."
		fi
		sleep 5
	done
	[ -z "$coco_enabled" ] && die "Confidential compute is expected but not enabled."
	info "ssh client output: ${coco_enabled}"
}

teardown() {
	if ! [[ " ${SUPPORTED_TEE_HYPERVISORS[@]} " =~ " ${KATA_HYPERVISOR} " ]] && ! [[ " ${SUPPORTED_NON_TEE_HYPERVISORS} " =~ " ${KATA_HYPERVISOR} " ]]; then
		skip "Test not supported for ${KATA_HYPERVISOR}."
	fi

	kubectl describe "pod/${pod_name}" || true
	kubectl delete -f "${pod_config_dir}/pod-confidential-unencrypted.yaml" || true
}
