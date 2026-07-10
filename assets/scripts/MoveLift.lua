-- MoveLift.lua
-- 時間経過で指定方向へ動くリフト用スクリプト。
-- 基準位置から axis * distance まで移動し、pingPong が true なら往復する。

properties = {
  -- リフトが動く方向。例: {0, 1, 0} で上下、{1, 0, 0} で左右。
  { name = "axis", type = "vec3", default = {0, 1, 0}, label = "移動方向" },

  -- 基準位置から最大でどれだけ離れるか。
  { name = "distance", type = "float", default = 3.0, min = 0.0, max = 50.0, label = "移動距離" },

  -- 片道にかかる秒数。pingPong が true の場合は、この秒数ごとに折り返す。
  { name = "duration", type = "float", default = 2.0, min = 0.1, max = 60.0, label = "片道時間" },

  -- true なら 0 -> 1 -> 0 の往復、false なら 0 -> 1 の後に0へ戻るループ。
  { name = "pingPong", type = "bool", default = true, label = "往復する" },

  -- true なら、リフト上にいる Player をリフトの移動量ぶん運ぶ。
  { name = "carryPlayer", type = "bool", default = true, label = "Playerを運ぶ" },

  -- リフト上面の判定サイズ。Transform Scale と掛け合わせた値で足場の横幅・高さになる。
  { name = "platformSize", type = "vec3", default = {3, 0.4, 1}, label = "足場判定サイズ(Scale前)" },

  -- Player の足元がリフト上面からこの距離以内なら、乗っているとみなす。
  { name = "rideSnapHeight", type = "float", default = 0.25, min = 0.01, max = 2.0, label = "乗る判定の高さ" },

  -- Player.lua の halfHeight と同じ値にすると、足元判定が合わせやすい。
  { name = "playerHalfHeight", type = "float", default = 0.8, min = 0.05, max = 5.0, label = "Player半分高さ" },
}

-- 0.0〜1.0の移動率を、往復またはループの設定に合わせて返す。
local function getMoveRate(self)
  local safeDuration = math.max(self.duration, 0.0001)

  if self.pingPong then
    local cycleTime = safeDuration * 2.0
    local t = self.elapsed % cycleTime

    -- 前半は 0 -> 1、後半は 1 -> 0 へ戻す。
    if t <= safeDuration then
      return t / safeDuration
    end

    return 1.0 - ((t - safeDuration) / safeDuration)
  end

  return (self.elapsed % safeDuration) / safeDuration
end

-- axis がゼロでも落ちないようにしつつ、移動方向を正規化して返す。
local function getNormalizedAxis(self)
  local x = self.axis.x or 0.0
  local y = self.axis.y or 0.0
  local z = self.axis.z or 0.0
  local length = math.sqrt(x * x + y * y + z * z)

  if length <= 0.0001 then
    return 0.0, 1.0, 0.0
  end

  return x / length, y / length, z / length
end

-- Transform Scale を反映した、リフトのワールド上の半分幅・半分高さを返す。
local function getPlatformHalfSize(self)
  local width = math.abs(self.platformSize.x or 1.0)
  local height = math.abs(self.platformSize.y or 1.0)

  -- Scale が取れる場合は、見た目と足場判定のサイズを合わせる。
  local ok, scale = pcall(function()
    return self.transform.scale
  end)

  if ok and scale then
    width = width * math.abs(scale.x or 1.0)
    height = height * math.abs(scale.y or 1.0)
  end

  return math.max(width * 0.5, 0.01), math.max(height * 0.5, 0.01)
end

-- Player の矢判定へ、リフトを命中対象として毎フレーム登録する。
local function sendArrowBounds(self)
  local position = self.transform.position
  local halfWidth, halfHeight = getPlatformHalfSize(self)

  events:emit("arrow_target_bounds", {
    target = self.name,
    tag = "MoveLift",
    x = position.x,
    y = position.y,
    width = halfWidth * 2.0,
    height = halfHeight * 2.0,
  })
end

-- Player の足元がリフト上面に近い場合、リフトに乗っていると判定する。
local function isPlayerRiding(self, player)
  local liftPosition = self.transform.position
  local playerPosition = player.transform.position
  local halfWidth, halfHeight = getPlatformHalfSize(self)
  local playerFootY = playerPosition.y - self.playerHalfHeight
  local platformTopY = liftPosition.y + halfHeight
  local horizontalInside = math.abs(playerPosition.x - liftPosition.x) <= halfWidth
  local verticalDistance = math.abs(playerFootY - platformTopY)

  return horizontalInside and verticalDistance <= self.rideSnapHeight
end

-- リフトの移動量を、すでに上に乗っている Player にも反映する。
local function carryRidingPlayer(self, player, deltaX, deltaY, deltaZ)
  if not self.carryPlayer then
    return
  end

  if not (player and player:isValid()) then
    return
  end

  local playerPosition = player.transform.position
  player.transform.position = Vec3.new(
    playerPosition.x + deltaX,
    playerPosition.y + deltaY,
    playerPosition.z + deltaZ)
end

function OnStart(self)
  local p = self.transform.position

  -- 開始位置をリフト移動の基準点として保存する。
  self.baseX, self.baseY, self.baseZ = p.x, p.y, p.z
  self.prevX, self.prevY, self.prevZ = p.x, p.y, p.z
  self.elapsed = 0.0

  -- Player より後に開始しても、初回フレームから矢の命中対象として見えるよう通知する。
  sendArrowBounds(self)
end

function OnUpdate(self, dt)
  self.elapsed = self.elapsed + dt

  local axisX, axisY, axisZ = getNormalizedAxis(self)
  local moveRate = getMoveRate(self)
  local moveDistance = self.distance * moveRate
  local nextX = self.baseX + axisX * moveDistance
  local nextY = self.baseY + axisY * moveDistance
  local nextZ = self.baseZ + axisZ * moveDistance
  local deltaX = nextX - self.prevX
  local deltaY = nextY - self.prevY
  local deltaZ = nextZ - self.prevZ
  local player = scene:findEntity("Player")
  local shouldCarryPlayer = self.carryPlayer and player and player:isValid() and isPlayerRiding(self, player)

  -- リフトが動く前の位置で乗っていたPlayerだけ、同じ移動量で運ぶ。
  self.transform.position = Vec3.new(nextX, nextY, nextZ)
  if shouldCarryPlayer then
    carryRidingPlayer(self, player, deltaX, deltaY, deltaZ)
  end

  -- 動いた後の位置を矢の当たり判定へ反映する。
  sendArrowBounds(self)

  self.prevX, self.prevY, self.prevZ = nextX, nextY, nextZ
end
