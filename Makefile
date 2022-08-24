# Multi architecture builds
TARGETS = amd64 arm64 ppc64le
PLATFORM = linux
BUILD_TARGETS = $(TARGETS:=.build)
BUILD_CI_TARGETS = $(TARGETS:=.docker)
IMAGE_PUSH_TARGETS = $(TARGETS:=.push-image)
MANIFEST_CREATE_TARGETS = $(PLATFORM:=.create-manifest)
MANIFEST_PUSH_TARGETS = $(PLATFORM:=.push-manifest)
BUILD_OPT=""
IMAGE_TAG=v1.1
IMAGE_PREFIX=fuse-device-plugin
IMAGE_REGISTRY ?= docker.io/soolaugust
BINARY=fuse-device-plugin


.DEFAULT_GOAL := build

# Build binary and docker and then push to docker hub
.PHONY: all
all: build docker push-image create-manifest push-manifest

# Build go binaries
PHONY: build $(BUILD_TARGETS)
build: $(BUILD_TARGETS)
%.build:
	TARGET=$(*) GOOS=linux GOARCH=$(*) CGO_ENABLED=0 GO111MODULE=on go build -o $(BINARY)-${PLATFORM}-$(*)

# Build docker image
PHONY: docker $(BUILD_CI_TARGETS)
docker: $(BUILD_CI_TARGETS)
%.docker:
	TARGET=$(*) docker build . --platform ${PLATFORM}/$(*) -t $(IMAGE_REGISTRY)/$(IMAGE_PREFIX):build-$(*)-${IMAGE_TAG} --build-arg build_arch=${PLATFORM}-${*}

#Docker image push
PHONY: push-image $(IMAGE_PUSH_TARGETS)
push-image: $(IMAGE_PUSH_TARGETS)
%.push-image:
	TARGET=$(*) docker push $(IMAGE_REGISTRY)/$(IMAGE_PREFIX):build-$(*)-${IMAGE_TAG}

# Create docker manifest for the targets
PHONY: create-manifest $(MANIFEST_CREATE_TARGETS)
create-manifest: $(MANIFEST_CREATE_TARGETS)
%.create-manifest:
	docker manifest create $(IMAGE_REGISTRY)/$(IMAGE_PREFIX):${IMAGE_TAG} $(foreach target,$(TARGETS), \
	-a $(IMAGE_REGISTRY)/$(IMAGE_PREFIX):build-$(target)-${IMAGE_TAG})
	@$(foreach target,$(TARGETS), \
	docker manifest annotate --arch $(target) $(IMAGE_REGISTRY)/$(IMAGE_PREFIX):${IMAGE_TAG} $(IMAGE_REGISTRY)/$(IMAGE_PREFIX):build-$(target)-${IMAGE_TAG} ; \
	)

# docker push manifest and inspect
PHONY: push-manifest $(MANIFEST_PUSH_TARGETS)
push-manifest: $(MANIFEST_PUSH_TARGETS)
%.push-manifest:
	docker manifest push $(IMAGE_REGISTRY)/$(IMAGE_PREFIX):${IMAGE_TAG}
	docker manifest inspect $(IMAGE_REGISTRY)/$(IMAGE_PREFIX):${IMAGE_TAG}

# Deployment
.PHONY: kustomize

yamls: kustomize
	kustomize edit set image fuse-device-plugin=$(IMAGE_REGISTRY)/$(IMAGE_PREFIX):${IMAGE_TAG}

deploy: yamls
	kustomize build . | kubectl apply -f -

undeploy: yamls
	kustomize build . | kubectl delete -f -

KUSTOMIZE = $(shell pwd)/bin/kustomize
kustomize: ## Download kustomize locally if necessary.
	$(call go-get-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v3@v3.8.7)
