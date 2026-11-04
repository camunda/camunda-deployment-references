prefix = "camunda-demo"

# One zone, three brokers, replication factor 3. Growing to a second region later adds a
# zone to this list; the brokers below keep their names (<zone>_0 .. <zone>_2).
zone = "zone-a"
zones = [
  { name = "zone-a", number_of_brokers = 3, number_of_replicas = 3, priority = 1000 },
]
