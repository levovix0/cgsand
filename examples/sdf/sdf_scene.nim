import sandbox
import sigeo/sdf


# A small scene built out of SDF primitives and operators:
# a row of mushrooms, made from a smooth union of a stem and a cap,
# repeated with `opLimitedRepetition`, standing on a ground slab.


# mushroom: tapered stem + dome cap, smoothly joined
let stem = sdRoundCone(p3(0, 0.1, 0), 0.55, 0.75, 1.5)
let cap = sdSphere(p3(0, 2, 0), 1.55)
  .opIntersection(sdPlane(p3(0, 1.45, 0), v3(0, -1, 0).NormalVec3))
let mushroom = stem.opSmoothUnion(cap, 0.3)
  .opLimitedRepetition(spacing = v3(5.4, 0, 0), limit = v3(1, 0, 0))

doc.add polygonalSurface3(mushroom.polygonize(step = 0.06))

# ground slab
doc.add polygonalSurface3(sdBox(p3(0, -0.2, 0), v3(9, 0.2, 9)).polygonize(step = 0.15))

# a pebble, to show `opSmoothIntersection` in the scene
doc.add polygonalSurface3(sdSphere(p3(4.6, 0.25, 2.4), 0.55)
  .opSmoothIntersection(sdSphere(p3(4.6, 0.55, 2.4), 0.7), 0.15)
  .polygonize(step = 0.04)):
  color(0.55, 0.55, 0.58)

