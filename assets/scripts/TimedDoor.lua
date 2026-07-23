-- TimedDoor.lua -- 「落とし格子(ポートカリス)」の可動格子。このスクリプトは格子エンティティ
-- (models/Gate_Grill)に付ける。石のフレーム(models/Gate_Frame)は別エンティティで飾りのみ。
-- 開閉は格子が物理的に上下にスライドする=当たり判定はAABBそのもの(solid_ghost等のハック不要)。
--   ・閉(格子が下りている): Player.solids で通行不可。矢の的にもなる
--   ・開くまで: openTに向けて格子がじわじわ持ち上がる(最大0.35=頭はくぐれない)=進捗が見える
--   ・開(openT到達): slideTimeかけて一気に引き上がり、下をくぐって通れる
--   ・閉鎖予告: closeTの1.2秒前からゆっくり降り始める=「今のうちに抜けろ」が見える
--   ・窓を逃した(closeT超過): 下りたまま赤い火花が明滅=矢では開かない、後戻りで呼び戻せの合図
-- 矢で先送りすると刺した量だけ時計が進む=格子が跳ね上がる。後戻りで時計ごと降りてくる。
properties = {
  { name = "openT",       type = "float", default = 8.0,   min = 0, max = 60,   label = "開く時刻(秒)" },
  { name = "closeT",      type = "float", default = 9999.0,min = 0, max = 9999, label = "閉じる時刻(秒。9999=開いたら閉じない)" },
  { name = "slideTime",   type = "float", default = 0.7,   min = 0.1, max = 3,  label = "全開までのスライド時間" },
  { name = "listenButton",type = "bool",  default = false,                      label = "ボタン連動(時間の代わりにボタンで開閉)" },
  { name = "arrowBoost",  type = "float", default = 4.0,   min = 1, max = 10,   label = "矢1秒で時計が進む倍率(フル溜め10秒×4=40秒分)" },
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
  self.riseHeight = self.transform.scale.y * 0.78  -- 全開時の引き上げ量(頭上まで抜ける)
  self.teaser = 0.35                               -- 開く前のじわじわ上昇の上限(くぐれない高さ)
  self.clock = 0
  self.buttonOpen = false
  self.ffRemain = 0
  self.rwGlow = 0
  self.redT = 0
  -- 閉門ゲート(openT=0で最初から開)は開いた状態で始める
  self.rise = (self.openT <= 0) and self.riseHeight or 0

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    -- 一括加算せず早送り(0.5秒で消化)して、格子が跳ね上がる様子を見せる
    -- 矢の秒数は arrowBoost 倍で効く(openTが長い錠ゲートも数発で開くように)
    self.ffRemain = self.ffRemain + data.amount * self.arrowBoost
    self.ffSpeed = self.ffRemain / 0.5
    FX.spark(self.bx, self.transform.position.y, self.bz, 10, 0.3, 0.75, 1.0)
    FX.shockwave(self.bx, self.transform.position.y, self.bz, 10, 6, 0.3, 0.9, 1.0)
  end)

  events:on("button_toggle", function(data)
    if data.target ~= self.name or not self.listenButton then return end
    self.buttonOpen = not self.buttonOpen
  end)

  -- 後戻り(グローバル): 上がった格子も時計と一緒に降りてくる。逃した窓も呼び戻せる
  events:on("time_rewind", function(data)
    if data.target ~= self.name then return end
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
  local target
  if self.listenButton then
    target = self.buttonOpen and self.riseHeight or 0
  else
    self.clock = self.clock + dt
    -- 閉門型: 閉まりきったら時計を止める(時間超過でRWが効かなくなる理不尽を防ぐ)。
    -- 以後は後戻し量=そのまま再開時間になる(RW-4なら4秒だけ開く)
    if self.closeT < 9000 and self.clock > self.closeT then
      self.clock = self.closeT
    end
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
        -- 返金は矢の実秒数ぶんだけ(倍率で時計が膨らんでも返金は膨らませない=無限時間の抜け道防止)
        events:emit("time_refund", { amount = step / self.arrowBoost })
      end
    end

    if self.clock >= self.closeT then
      target = 0                                   -- 窓を逃した(赤明滅は下で)
    elseif self.clock >= self.openT then
      target = self.riseHeight
      local untilClose = self.closeT - self.clock
      if untilClose < 1.2 then                     -- 閉鎖予告: ゆっくり降り始める
        target = self.riseHeight * (untilClose / 1.2)
      end
    else
      -- 開くまでのじわじわ上昇(進捗表示。くぐれる高さにはならない)
      target = self.teaser * (self.clock / math.max(self.openT, 0.01))
    end
  end

  -- 目標へ一定速度で追従(早送り消化中は時計が速いぶん自然に跳ね上がる)
  local speed = self.riseHeight / math.max(self.slideTime, 0.1)
  if self.rise < target then
    self.rise = math.min(target, self.rise + speed * dt)
  elseif self.rise > target then
    self.rise = math.max(target, self.rise - speed * dt)
  end
  local y = self.by + self.rise
  self.transform.position = Vec3.new(self.bx, y, self.bz)

  -- 窓を逃した合図: 赤い火花が明滅(矢は効かない、後戻りで呼び戻せ)
  if not self.listenButton and self.clock >= self.closeT then
    self.redT = self.redT + dt
    if self.redT > 0.6 then
      self.redT = 0
      FX.spark(self.bx, y + self.transform.scale.y * 0.45, self.bz, 8, 1.0, 0.2, 0.15)
    end
  end

  -- ゲート状態の色: 開いていく=青(10.x) / 閉まっていく・閉鎖=ピンク(11.x, 後戻りの示唆)
  local gateEff = nil
  if self.listenButton then
    if self.rise < target - 0.01 then gateEff = 10.9      -- ボタンで開いていく
    elseif self.rise > target + 0.01 then gateEff = 11.6  -- ボタンで閉まっていく
    end
  else
    if self.clock >= self.closeT then
      gateEff = 11.9                                      -- 窓を逃して閉鎖: 後戻りで呼び戻せ
    elseif self.clock >= self.openT then
      if self.closeT - self.clock < 1.2 then gateEff = 11.5    -- 閉鎖予告で降下中
      elseif self.rise < target - 0.01 then gateEff = 10.9     -- 全開へ引き上げ中
      end
    elseif self.openT > 0 then
      gateEff = 10.15 + 0.55 * (self.clock / self.openT)  -- 開くまでの充填: 青がじわじわ強まる
    end
  end

  -- シェーダー: 撃てる=金色 / FF=シアン / RW=紫 / 開閉状態=青・ピンク
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = gateEff or 5.0
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

  -- 早送り=水色 / 後戻り=紫 の残像
  if self.ffRemain > 0 then
    FX.trail(self.bx, y, self.bz, 0.3, 0.9, 1.0)
  end
  if self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(self.bx, y, self.bz, 0.65, 0.4, 1.0)
  end
end
