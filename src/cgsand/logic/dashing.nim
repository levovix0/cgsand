import ../lib/[sandbox]


iterator dashedSegments*(
  points: openArray[Point2],
  dashing: Dashing,
  scale: float = 1,
): tuple[a, b: Point2] =
  ## yields the line segments (and dots, as zero-length a==b segments) that make up
  ## the given polyline stroked with the given dashing pattern.
  ##
  ## the pattern is automatically scaled so that:
  ##   a dash is always drawn at the very start and (for open curves) the very end of the curve
  ##   the number of pattern repetitions stays close to the unscaled one, but always >= minRepeats
  const minRepeats = 2

  if points.len >= 2:
    if dashing.pattern.len == 0:
      for i in 0 ..< points.len - 1:
        yield (points[i], points[i + 1])
    else:
      # total length of the polyline, and whether it forms a closed loop
      var total = 0.0
      for i in 0 ..< points.len - 1:
        total += points[i].distanceTo(points[i + 1])
      let closed = points[0] ~== points[^1]

      var pat = dashing.pattern
      if scale != 1:
        for i in 0 ..< pat.len:
          pat[i] *= scale

      let cycleLen = pat.sum
      if cycleLen > 0 and total > 0:
        ## for an open curve, drop the tail of the last cycle that comes after its last positive-length dash,
        ## so the curve always ends on a drawn line (not a gap or a dot).
        ## e.g. for [dash, gap, dot, gap] this drops [gap, dot, gap].
        var trailingGap = 0.0
        if not closed:
          var lastDash = -1
          for i in 0 ..< pat.len:
            if (i mod 2) == 0 and pat[i] > 0:
              lastDash = i
          if lastDash >= 0:
            for i in lastDash + 1 ..< pat.len:
              trailingGap += pat[i]

        let reps = max(minRepeats, round(total / cycleLen).int)
        let target = reps.float * cycleLen - trailingGap
        if target > 0:
          let s = total / target
          for i in 0 ..< pat.len:
            pat[i] *= s

      template isDash(idx: int): bool = (idx mod 2) == 0

      var patIdx = 0
      var patRemaining = pat[0]

      # emit a leading dot if the pattern starts with a zero-length dash
      if isDash(patIdx) and pat[patIdx] == 0:
        yield (points[0], points[0])
        patIdx = (patIdx + 1) mod pat.len
        patRemaining = pat[patIdx]

      for i in 0 ..< points.len - 1:
        let a = points[i]
        let b = points[i + 1]
        let segLen = a.distanceTo(b)
        if segLen <= 0: continue
        let dir = (b - a) / segLen
        var pos = 0.0
        while pos < segLen - 1e-9:
          if patRemaining <= 0:
            patIdx = (patIdx + 1) mod pat.len
            patRemaining = pat[patIdx]
            if isDash(patIdx) and pat[patIdx] == 0:
              yield (a + dir * pos, a + dir * pos)
              patIdx = (patIdx + 1) mod pat.len
              patRemaining = pat[patIdx]
            continue
          let step = min(patRemaining, segLen - pos)
          if isDash(patIdx):
            yield (a + dir * pos, a + dir * (pos + step))
          pos += step
          patRemaining -= step

