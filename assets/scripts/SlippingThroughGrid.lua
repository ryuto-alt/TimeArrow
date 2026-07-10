-- SlippingThroughGrid.lua
-- プレイヤーは通れないが、矢は通り抜けられる柵用スクリプト。
-- Arrow は判定対象にせず、Player の位置だけを柵の矩形外へ押し戻す。

properties = {
  -- 柵の当たり判定サイズ。Transform Scale と掛け合わせた値がワールド上の幅・高さになる。
  { name = "hitBoxSize", type = "vec3", default = {1, 1, 1}, label = "柵の判定サイズ(Scale前)" },

  -- Player の横幅・高さ。Player.lua の見た目や halfHeight に合わせて調整する。
  { name = "playerHalfWidth", type = "float", default = 0.45, min = 0.05, max = 5, label = "Player半分幅" },
  { name = "playerHalfHeight", type = "float", default = 0.8, min = 0.05, max = 5, label = "Player半分高さ" },

  -- true の場合は、押し戻し方向を画面に表示して調整しやすくする。
  { name = "showDebug", type = "bool", default = false, label = "デバッグ表示" },
}

-- 値を minValue 以上 maxValue 以下へ収める。
local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end

  return value
end

-- Transform Scale を反映した、柵のワールド上の半分幅・半分高さを返す。
local function getGridHalfSize(self)
  local width = math.abs(self.hitBoxSize.x or 1.0)
  local height = math.abs(self.hitBoxSize.y or 1.0)

  -- Scale を読める場合は、見た目の拡大縮小と当たり判定をそろえる。
  local ok, scale = pcall(function()
    return self.transform.scale
  end)

  if ok and scale then
    width = width * math.abs(scale.x or 1.0)
    height = height * math.abs(scale.y or 1.0)
  end

  return math.max(width * 0.5, 0.01), math.max(height * 0.5, 0.01)
end

-- Player と柵のAABBが重なっている場合、押し戻しに必要なX/Y量を返す。
local function getPlayerPushOut(self, playerPosition)
  local gridPosition = self.transform.position
  local gridHalfWidth, gridHalfHeight = getGridHalfSize(self)
  local playerHalfWidth = math.max(self.playerHalfWidth, 0.01)
  local playerHalfHeight = math.max(self.playerHalfHeight, 0.01)

  local dx = playerPosition.x - gridPosition.x
  local dy = playerPosition.y - gridPosition.y
  local overlapX = gridHalfWidth + playerHalfWidth - math.abs(dx)
  local overlapY = gridHalfHeight + playerHalfHeight - math.abs(dy)

  -- どちらかの軸で重なっていなければ、柵には触れていない。
  if overlapX <= 0 or overlapY <= 0 then
    return nil, nil
  end

  -- めり込みが浅い軸だけを押し戻すと、角で引っかかりにくい。
  if overlapX < overlapY then
    local sign = dx < 0 and -1 or 1
    return overlapX * sign, 0
  end

  local sign = dy < 0 and -1 or 1
  return 0, overlapY * sign
end

-- Player を柵の外へ戻す。矢は対象にしないため、そのまま通り抜ける。
local function blockPlayerOnly(self)
  local player = scene:findEntity("Player")
  if not (player and player:isValid()) then
    return
  end

  local playerPosition = player.transform.position
  local pushX, pushY = getPlayerPushOut(self, playerPosition)
  if pushX == nil then
    return
  end

  -- 極端なめり込みで大きく飛ばないよう、1回の補正量を少しだけ制限する。
  local safePushX = clamp(pushX, -2.0, 2.0)
  local safePushY = clamp(pushY, -2.0, 2.0)

  player.transform.position = Vec3.new(
    playerPosition.x + safePushX,
    playerPosition.y + safePushY,
    playerPosition.z)

  if self.showDebug then
    ui:text(20, 132, "Grid Push: " .. safePushX .. ", " .. safePushY, 16, 0.5, 0.9, 1, 1)
  end
end

function OnStart(self)
  -- 開始時点では保持する状態はない。毎フレーム Player の現在位置だけを見て判定する。
end

function OnUpdate(self, dt)
  -- dt は今回の押し戻し計算では不要だが、OnUpdate の引数として受け取っておく。
  blockPlayerOnly(self)
end
