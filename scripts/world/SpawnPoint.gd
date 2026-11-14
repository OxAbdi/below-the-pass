extends Marker2D
## A place James can arrive at, with the way he faces when he gets there.
## Put these under a map's "Spawns" node. The node's name is the spawn id.
## (A plain Marker2D works too. James then faces the camera.)

@export_enum("E", "SE", "S", "SW", "W", "NW", "N", "NE") var facing: String = "S"
