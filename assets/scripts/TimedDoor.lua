-- TimedDoor.lua -- 「閉まるドア・ゴール」= 本物の障害物。閉まっている間はPlayer.solids経由で
-- 物理的に通行不可(既定では死なない、ただ塞ぐだけ)。[openT, closeT) の間だけ沈んで通行可になる。
-- 矢で先送りすると窓へ滑り込ませられるが、引きすぎると窓を通り過ぎてまた閉まる
-- (=オーバーシュート。引き量の見極めがパズルになる)。listenButton=trueならボタンで開閉をトグルできる
-- (この場合 openT/closeT の時間窓は無視され、ボタン状態がそのまま開閉を決める)。
-- deadly=trueにすると閉状態への接触も即死にできる(トゲ付きゲート等、任意)。
properties = {
  { name = "openT",       type = "float", default = 8.0,  min = 0, max = 60, label = "開き始める時刻(秒)" },
  { name = "closeT",      type = "float", default = 11.0, min = 0, max = 60, label = "閉じる時刻(秒)" },
  { name = "sinkAmount",  type = "float", default = 2.6,  min = 0, max = 10, label = "開いた時に沈む量" },
  { name = "listenButton",type = "bool",  default = false,                   label = "ボタン連動(時間窓の代わりにボタンで開閉)" },
  { name = "deadly",      type = "bool",  default = false,                   label = "閉まってる間に触れると死ぬ(任意、既定は物理ブロックのみ)" },
  { name = "hitScale",    type = "float", default = 0.8,  min = 0.2, max = 1.5,label = "deadly時の当たり判定倍率" },
}

local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = 0
  self.buttonOpen = false

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    self.clock = self.clock + data.amount
    FX.spark(self.bx, self.by, self.bz, 10, 0.3, 0.75, 1.0)
  end)

  events:on("button_toggle", function(data)
    if data.target ~= self.name or not self.listenButton then return end
    self.buttonOpen = not self.buttonOpen
  end)
end

function OnUpdate(self, dt)
  local open
  if self.listenButton then
    open = self.buttonOpen
  else
    self.clock = self.clock + dt
    open = self.clock >= self.openT and self.clock < self.closeT
  end

  local y = open and (self.by - self.sinkAmount) or self.by
  self.transform.position = Vec3.new(self.bx, y, self.bz)

  if open or not self.deadly then return end
  local s = self.transform.scale
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp, ps = pl.transform.position, pl.transform.scale
  if overlapAABB(self.bx, self.by, s.x * 0.5 * self.hitScale, s.y * 0.5 * self.hitScale, pp.x, pp.y, ps.x * 0.5, ps.y * 0.5) then
    events:emit("player_died", {})
  end
end
