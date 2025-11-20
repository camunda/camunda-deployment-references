# Double check the config against the unified config

camunda:
  security:
    authentication:
      method: basic
      unprotectedApi: true
    authorizations:
      enabled: false
    initialization:
      users:
        - username: demo
          password: demo
          name: "Demo User"
          email: "demo@example.com"
      defaultRoles:
        admin:
          - demo
