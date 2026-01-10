-- cr-3dnui/client/util/vec.lua
-- Small vector helpers used across modules

CR3D = CR3D or {}

function CR3D.vecAdd(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
function CR3D.vecSub(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
function CR3D.vecMul(a, s) return vector3(a.x * s, a.y * s, a.z * s) end
function CR3D.vecDot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function CR3D.vecCross(a, b)
  return vector3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x
  )
end
function CR3D.vecLen(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end

-- Fast squared distance (no sqrt) for comparisons
function CR3D.vecDistSq(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return dx * dx + dy * dy + dz * dz
end

function CR3D.vecNorm(a)
  local len = CR3D.vecLen(a)
  if len < 0.0001 then return vector3(0.0, 0.0, 0.0) end
  return vector3(a.x / len, a.y / len, a.z / len)
end

-- camera rotation → direction
function CR3D.rotationToDirection(rot)
  local radX = math.rad(rot.x)
  local radZ = math.rad(rot.z)
  local cosX = math.cos(radX)
  local sinX = math.sin(radX)
  local cosZ = math.cos(radZ)
  local sinZ = math.sin(radZ)
  return vector3(-sinZ * cosX, cosZ * cosX, sinX)
end
