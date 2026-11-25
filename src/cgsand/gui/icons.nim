import pixie

proc distanceToSegment(p, a, b: Vec2): float32 =
  let ab = b - a
  let ap = p - a
  let t = clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0)
  let closestPoint = a + ab * t
  return dist(p, closestPoint)

proc antialiasedIcon(sz: int32, thickness: float32, color: Color, combinedDist: proc(p: Vec2): float32): Image =
  ## paints pixels of an icon defined by `combinedDist` returning the distance
  ## to the nearest drawn line (positive outside)
  let image = newImage(sz, sz)
  for y in 0..<sz:
    for x in 0..<sz:
      let idx = y * sz + x
      let p = vec2(x.float, y.float)
      let intensity = 1.0 - clamp(abs(combinedDist(p)) / thickness, 0.0, 1.0)
      if intensity > 0.0:
        let alpha = color.a * intensity
        image.data[idx] = rgbx(
          uint8(color.r * alpha * 255.0),
          uint8(color.g * alpha * 255.0),
          uint8(color.b * alpha * 255.0),
          uint8(alpha * 255.0),
        )
  return image

proc sdRoundBox(p, b: Vec2, r: float32): float32 =
  ## SDF for a rounded rectangle centered at (0,0), with half-dimensions b and radius r
  let q = abs(p) - b + vec2(r, r)
  min(max(q.x, q.y), 0.0'f32) + length(max(q, vec2(0.0'f32, 0.0'f32))) - r

proc sdSegment(p, a, b: Vec2): float32 =
  ## SDF for a segment from a to b
  let pa = p - a
  let ba = b - a
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0'f32, 1.0'f32)
  length(pa - ba * h)

proc filesIcon*(scale: float32, color: Color = color(1, 1, 1)): Image =
  ## VS Code style explorer icon: two sheets with rounded corners and a bent edge
  let sz = (32 * scale).round.int32
  let thickness = 1.6 * scale
  let s = scale

  # Parameters for the front sheet
  let fMin = vec2(10.0 * s, 5.0 * s)
  let fMax = vec2(25.0 * s, 24.0 * s)
  let fCenter = (fMin + fMax) * 0.5'f32
  let fHalf = (fMax - fMin) * 0.5'f32
  let radius = 2.2 * s
  let foldSize = 5.5 * s # Size of the bent corner

  # The back sheet is offset to the left and down relative to the front
  let offset = vec2(-3.5 * s, 3.5 * s)
  let bCenter = fCenter + offset

  proc combinedDist(p: Vec2): float32 =
    # Front sheet (cut the top-right corner with a diagonal plane)
    let boxFront = sdRoundBox(p - fCenter, fHalf, radius)
    # Cut normal at 45 degrees: (1, -1) / sqrt(2)
    let cutPlane = ((p.x - (fMax.x - foldSize)) - (p.y - fMin.y)) * 0.70710678'f32
    let frontShape = max(boxFront, cutPlane)
    let frontOutline = abs(frontShape)

    # Corner fold lines (inner corner)
    let corner = vec2(fMax.x - foldSize, fMin.y + foldSize)
    let foldH = sdSegment(p, vec2(fMax.x - foldSize, fMin.y), corner)
    let foldV = sdSegment(p, corner, vec2(fMax.x, fMin.y + foldSize))
    let foldLines = min(foldH, foldV)

    # Back sheet (cutting the area overlapped by the front sheet, considering the line thickness)
    let boxBack = sdRoundBox(p - bCenter, fHalf, radius)
    let backOutline = max(abs(boxBack), -(frontShape - thickness * 0.85'f32))

    min(min(frontOutline, foldLines), backOutline)

  result = antialiasedIcon(sz, thickness, color, combinedDist)

proc sceneTreeIcon*(scale: float32, color: Color = color(1, 1, 1)): Image =
  ## Icon for a build tree (Outline / Hierarchy)
  let sz = (32 * scale).round.int32
  let thickness = 1.6 * scale
  let s = scale
  let r = 1.2 * s

  proc combinedDist(p: Vec2): float32 =
    # Root node (top rectangle)
    let rootBox = abs(sdRoundBox(p - vec2(12.5 * s, 7.5 * s), vec2(5.5 * s, 2.2 * s), r))

    # Child nodes (shifted to the right)
    let child1 = abs(sdRoundBox(p - vec2(19.5 * s, 16.0 * s), vec2(6.0 * s, 2.2 * s), r))
    let child2 = abs(sdRoundBox(p - vec2(19.5 * s, 24.5 * s), vec2(6.0 * s, 2.2 * s), r))

    # Tree connecting lines (trunk and branches)
    let trunk = sdSegment(p, vec2(9.5 * s, 9.7 * s), vec2(9.5 * s, 24.5 * s))
    let branch1 = sdSegment(p, vec2(9.5 * s, 16.0 * s), vec2(13.5 * s, 16.0 * s))
    let branch2 = sdSegment(p, vec2(9.5 * s, 24.5 * s), vec2(13.5 * s, 24.5 * s))

    let nodes = min(rootBox, min(child1, child2))
    let lines = min(trunk, min(branch1, branch2))
    min(nodes, lines)

  result = antialiasedIcon(sz, thickness, color, combinedDist)

proc maximizeIcon*(scale: float32): Image =
  let sz = (32 * scale).round.int32
  let myImage = newImage(sz, sz)
  
  let thickness = 1.5 * scale
  let cornerRadius = 4.0 * scale

  let center = vec2((sz.float - 1.0) / 2.0, (sz.float - 1.0) / 2.0)
  
  let pad = 9.0 * scale
  let halfWidth = (sz.float - 1.0) / 2.0 - pad
  let halfHeight = (sz.float - 1.0) / 2.0 - pad
  let boxHalfSizes = vec2(halfWidth, halfHeight)

  for y in 0..<sz:
    for x in 0..<sz:
      let idx = y * sz + x
      
      let p = vec2(x.float, y.float) - center

      let q = vec2(abs(p.x) - boxHalfSizes.x + cornerRadius, abs(p.y) - boxHalfSizes.y + cornerRadius)
      
      let extDist = dist(max(q, 0.0), vec2(0.0, 0.0))
      let intDist = min(max(q.x, q.y), 0.0)
      
      let distToBox = extDist + intDist - cornerRadius
      
      let distToOutline = abs(distToBox)
      
      var intensity = 1.0 - (distToOutline / thickness)
      intensity = clamp(intensity, 0.0, 1.0)
      
      if intensity > 0.0:
        let alpha = uint8(intensity * 255.0)
        let colorValue = uint8(255.0 * intensity)
        myImage.data[idx] = rgbx(colorValue, colorValue, colorValue, alpha)
          
  return myImage

proc minimizeIcon*(scale: float32): Image =
  let sz = (32 * scale).round.int32
  let myImage = newImage(sz, sz)
  
  let thickness: float = 1.5 * scale
  let pad: float = 9.0 * scale
  
  let centerY = (sz.float - 1.0) / 2.0
  let pointA = vec2(pad, centerY + sz / 6)
  let pointB = vec2(sz.float - 1.0 - pad, centerY + sz / 6)

  for y in 0..<sz:
    for x in 0..<sz:
      let idx = y * sz + x
      let p = vec2(x.float, y.float)

      let minDist = distanceToSegment(p, pointA, pointB)
      
      var intensity = 1.0 - (minDist / thickness)
      intensity = clamp(intensity, 0.0, 1.0)
      
      if intensity > 0.0:
        let alpha = uint8(intensity * 255.0)
        let colorValue = uint8(255.0 * intensity)
        myImage.data[idx] = rgbx(colorValue, colorValue, colorValue, alpha)
          
  return myImage

proc closeIcon*(scale: float32): Image =
  let sz = (32 * scale).round.int32
  let myImage = newImage(sz, sz)
  
  let thickness = 1.5 * scale
  let pad = 9.0 * scale
  let maxPos = sz.float - 1.0 - pad

  let a1 = vec2(pad, pad)
  let b1 = vec2(maxPos, maxPos)
  
  let a2 = vec2(maxPos, pad)
  let b2 = vec2(pad, maxPos)

  for y in 0..<sz:
    for x in 0..<sz:
      let idx = y * sz + x
      let p = vec2(x.float, y.float)

      let distMain = distanceToSegment(p, a1, b1)
      let distAnti = distanceToSegment(p, a2, b2)
      
      let minDist = min(distMain, distAnti)
      
      var intensity = 1.0 - (minDist / thickness)
      intensity = clamp(intensity, 0.0, 1.0)
      
      if intensity > 0.0:
        let alpha = uint8(intensity * 255.0)
        let colorValue = uint8(255.0 * intensity)
        myImage.data[idx] = rgbx(colorValue, colorValue, colorValue, alpha)
              
  return myImage
