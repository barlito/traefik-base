stack_name=traefik

.PHONY: deploy
deploy:
	docker stack deploy -c docker-compose.yml $(stack_name)

.PHONY: undeploy
undeploy:
	docker stack rm $(stack_name)
