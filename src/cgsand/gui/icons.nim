import pixie

proc distanceToSegment(p, a, b: Vec2): float32 =
  let ab = b - a
  let ap = p - a
  let t = clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0)
  let closestPoint = a + ab * t
  return dist(p, closestPoint)

proc maximizeIcon*(): Image = 
    let sz = 32
    let myImage = newImage(sz, sz)
    
    let thickness = 1.5
    let cornerRadius = 4.0

    let center = vec2((sz.float - 1.0) / 2.0, (sz.float - 1.0) / 2.0)
    
    let pad = 9.0
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

proc minimizeIcon*(): Image = 
    let sz = 32
    let myImage = newImage(sz, sz)
    
    let thickness: float = 1.5
    let pad: float = 9.0
    
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

proc closeIcon*(): Image = 
    let sz = 32
    let myImage = newImage(sz, sz)
    
    let thickness = 1.5
    let pad = 9.0
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