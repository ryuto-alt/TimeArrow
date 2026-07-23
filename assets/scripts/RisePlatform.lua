-- RisePlatform.lua -- arriveT まで「着地点の上空(余白)」に薄く浮かんで待機している足場。
-- 画面外からいきなり出てくるのではなく、最初から見えている=どこに橋が架かるか予告になる。
-- 時が来る(or 矢で先送りする)と ease-out でゆっくり降りてきて、着地の瞬間に衝撃波。
-- listenButton=true ならボタン連動リフトになり、押すたびに上下をトグルする(時間無視)。
-- Player.lua の standables に名前を入れれば乗れる(待機中は上空なので実質届かない)。
properties = {
  { name = "arriveT",     type = "float",  default = 10.0, min = 0,   max = 60, label = "降りてくる時刻(秒)" },
  { name = "riseTime",    type = "float",  default = 0.9,  min = 0.05,max = 3,  label = "降下にかかる時間(急にばん!と来ない)" },
  { name = "waitHeight",  type = "float",  default = 5.5,  min = 1,   max = 20, label = "待機する高さ(着地点からの上空オフセット)" },
  { name = "triggerName", type = "string", default = "",                       label = "矢が当たる的の名前(空なら自分の名前)" },
  { name = "listenButton",type = "bool",   default = false,                    label = "ボタン連動リフト(押すたびに上下をトグル)" },
  { name = "reverse",     type = "bool",   default = false,                    label = "逆モード: 設置位置から上空へ上がっていく(後戻しで引き戻す)" },
  { name = "arrowBoost",  type = "float",  default = 4.0,  min = 1,   max = 10,label = "矢1秒で時計が進む倍率(序盤の1発でもarriveTに届くように)" },
}

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  events:on("aim_preview", function(d)
    if d.target == self.name or d.target == self.name .. "X" then
      self.aimPv = { m = d.mode, t = 0.12 }
    end
  end)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.waitY = self.by + self.waitHeight
  self.clock = 0
  self.buttonUp = false
  self.curFrac = 0
  self.prevFrac = 0
  self.ffRemain = 0
  self.transform.position = Vec3.new(self.bx, self.reverse and self.by or self.waitY, self.bz)

  local listenName = self.triggerName ~= "" and self.triggerName or self.name
  events:on("time_skip", function(data)
    if data.target ~= listenName then return end
    -- 一括加算せず早送り(0.5秒で消化)して、降りてくる様子が見えるようにする。
    -- どんなに軽い矢でも最低「到着まで」は進める(arriveTが遠いと無反応に見えるのを防ぐ)
    local need = (self.arriveT + self.riseTime) - self.clock
    self.ffRemain = math.max(self.ffRemain + data.amount * self.arrowBoost, need)
    self.ffSpeed = self.ffRemain / 0.5
    FX.spark(self.bx, self.transform.position.y, self.bz, 12, 0.3, 0.75, 1.0)
  end)

  events:on("button_toggle", function(data)
    if data.target ~= self.name or not self.listenButton then return end
    self.buttonUp = not self.buttonUp
    FX.spark(self.bx, self.transform.position.y, self.bz, 10, 0.3, 0.75, 1.0)
  end)

  -- 後戻り(グローバル): 降りた橋も戻せば上空へ帰っていく
  self.rwGlow = 0
  events:on("time_rewind", function(data)
    if data.target ~= listenName then return end
    -- 後戻り矢: 一括減算せず逆再生(0.5秒で消化)して、巻き戻る様子を見せる(FFと同倍率)
    self.rwRemain = (self.rwRemain or 0) + (data.amount or 0) * self.arrowBoost
    self.rwSpeed = self.rwRemain / 0.5
    self.rwGlow = 0.1
    local p = self.transform.position
    FX.spark(p.x, p.y, p.z, 10, 0.65, 0.4, 1.0)
    FX.shockwave(p.x, p.y, p.z, 10, 6, 0.65, 0.4, 1.0)
  end)
end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)  -- 弓の構え中はスローモーション
  local frac
  if self.listenButton then
    -- ボタンはトグルの瞬間値しか持たないので、ここだけ滑らかに追従させる
    local targetFrac = self.buttonUp and 1 or 0
    local step = dt / math.max(self.riseTime, 0.05)
    if self.curFrac < targetFrac then
      self.curFrac = math.min(targetFrac, self.curFrac + step)
    else
      self.curFrac = math.max(targetFrac, self.curFrac - step)
    end
    frac = self.curFrac
  else
    self.clock = self.clock + dt
    if self.ffRemain > 0 then
      local step = math.min(self.ffRemain, self.ffSpeed * dt)
      self.clock = self.clock + step
      self.ffRemain = self.ffRemain - step
    end
    if self.rwRemain and self.rwRemain > 0 then
      -- 対象の時計は0で底打ち。それ以上は戻せない=タイマー返金もされない(戻しすぎは無駄撃ち)
      local step = math.min(self.rwRemain, self.rwSpeed * dt, self.clock)
      if step <= 0 then
        self.rwRemain = 0
      else
        self.clock = self.clock - step
        self.rwRemain = self.rwRemain - step
        self.rwGlow = 0.1
        -- 返金は矢の実秒数ぶんだけ(倍率ぶんの水増し返金はしない)
        events:emit("time_refund", { amount = step / self.arrowBoost })
      end
    end
    -- 完了後は時計停止(扉と同じ「終わった機構は時計が止まる」ルール)=いつでも後戻しが効く
    local doneT = self.arriveT + self.riseTime
    if self.clock > doneT then self.clock = doneT end
    frac = clamp((self.clock - self.arriveT) / self.riseTime, 0, 1)
  end

  -- 等速で降下する。riseTimeを制限時間より長く(例:12秒)すれば「ずっとゆっくり落ちてきていて、
  -- 放っておくと10秒では間に合わない橋」になる=矢の先送りで降下を進めるのが本筋になる
  local y = self.reverse and lerp(self.by, self.waitY, frac) or lerp(self.waitY, self.by, frac)
  self.transform.position = Vec3.new(self.bx, y, self.bz)

  -- 着地の瞬間だけ衝撃波(降下は静かに、到着で一拍)
  if self.prevFrac < 1 and frac >= 1 then
    FX.shockwave(self.bx, self.by, self.bz, 12, 6, 0.4, 0.85, 1.0)
    fx:pulse(0.1)
  end
  self.prevFrac = frac

  -- TimeWarpシェーダーへ状態を送る: 早送り=1 / 後戻り=2.8 /
  -- まだ着地していない(降下中・待機中)=0.35の弱い早送り風シマー(実体前の予告) / 着地済み=0
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 0  -- 橋は普段は光らせない(FF=シアン/RW=紫のときだけ)
    if self.ffRemain > 0 then eff = 1.0
    elseif self.rwGlow > 0 then eff = 2.8 end
    if self.aimPv then
      self.aimPv.t = self.aimPv.t - dt
      if self.aimPv.t > 0 then
        eff = (self.aimPv.m == "rewind") and 9.5 or 8.5
      else
        self.aimPv = nil
      end
    end
    scene:setMeshEffect(selfE, eff)
  end

  -- 降下中は白いトレイル、早送り=水色 / 後戻り=紫
  if frac > 0 and frac < 1 then
    FX.trail(self.bx, y, self.bz, 0.7, 0.85, 1.0)
  end
  if self.ffRemain > 0 then
    FX.trail(self.bx, y, self.bz, 0.3, 0.9, 1.0)
  end
  if self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(self.bx, y, self.bz, 0.65, 0.4, 1.0)
  end
end
