import sandbox, geom2d
import pkg/vmath
import pkg/pixie/paths

## utility function to copy contents of a techDraw world onto another with Transform3 applied
## needed in rare cases, usually just adding a SubWorld works


proc explode*(dest: World, subWorld: World, transform: Transform3 = m4()) =
  ## copies every drawable entity from `subWorld` into `dest`, applying `transform`.
  ## only entities that carry a drawable thing are copied
  subWorld.forEach (
    eid: EntityId,
    LineSection2|CircleArc2|EllipseArc2|Curve2|OwnedCurve2|Path2|Path|Text|SubWorld|PolygonalSurface3,
    opt Transform3
  ):
    let newEid = dest.teleportClone(subWorld, eid)

    if has Transform3:
      dest[newEid, Transform3] = Transform3(transform * the(Transform3))
    else:
      dest.update newEid: add transform

