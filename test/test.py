"""Pruebas por pines, aptas para RTL y netlist. Modelo entero independiente."""
import math
import random
import cocotb
from cocotb.triggers import Timer

LUT = [round(127 * math.sin(2 * math.pi * k / 32)) for k in range(32)]


class Model:
    def __init__(self, step=4096, window=256):
        self.step, self.window = step, window
        self.phase = self.si = self.sq = self.count = 0

    def feed(self, x):
        a = self.phase >> 11
        self.si += x * LUT[(a + 8) % 32]
        self.sq -= x * LUT[a]
        self.phase = (self.phase + self.step) % 65536
        self.count += 1
        if self.count == self.window:
            pair = self.si // self.window, self.sq // self.window
            self.si = self.sq = self.count = 0
            return pair
        return None


class Bus:
    def __init__(self, d):
        self.d = d

    async def cycle(self, n=1):
        for _ in range(n):
            self.d.clk.value = 0
            await Timer(10, unit="ns")
            self.d.clk.value = 1
            await Timer(10, unit="ns")
            self.d.clk.value = 0

    async def reset(self):
        self.d.clk.value = 0
        self.d.rst_n.value = 0
        self.d.ena.value = 1
        self.d.ui_in.value = 0
        self.d.uio_in.value = 0
        await self.cycle(3)
        self.d.rst_n.value = 1
        await self.cycle()
        assert int(self.d.uio_oe.value) == 0xC0

    async def write(self, addr, data):
        self.d.ui_in.value = data
        self.d.uio_in.value = addr << 2
        await self.cycle()
        self.d.uio_in.value = (addr << 2) | 2
        await self.cycle()
        self.d.uio_in.value = addr << 2
        await self.cycle()

    async def read(self, addr):
        self.d.uio_in.value = addr << 2
        await Timer(1, unit="ns")
        return int(self.d.uo_out.value)

    async def snapshot(self):
        self.d.uio_in.value = 0
        await self.cycle()
        self.d.uio_in.value = 32
        await self.cycle()
        self.d.uio_in.value = 0
        await self.cycle()
        return await self.read_pair()

    async def read_pair(self):
        b = [await self.read(a) for a in range(4)]
        words = [b[0] | b[1] << 8, b[2] | b[3] << 8]
        return tuple(x if x < 32768 else x - 65536 for x in words)

    async def sample(self, x, gap=0):
        assert not (int(self.d.uio_out.value) & 64), "busy before sample"
        self.d.ui_in.value = x & 255
        self.d.uio_in.value = 1
        await self.cycle()
        assert int(self.d.uio_out.value) & 64
        self.d.uio_in.value = 0
        await self.cycle(3 + gap)
        assert not (int(self.d.uio_out.value) & 64)

    async def configure(self, step, sel):
        await self.write(4, step & 255)
        await self.write(5, step >> 8)
        await self.write(6, sel)


@cocotb.test()
async def numeric_windows_and_frequencies(d):
    bus = Bus(d)
    await bus.reset()
    rng = random.Random(260917)
    for sel, n in enumerate((16, 64, 256, 1024)):
        for step in (0, 4096, 12345, 65535):
            await bus.configure(step, sel)
            model = Model(step, n)
            for k in range(2*n):
                x = (-128,127,0)[k%3] if k < n else rng.randrange(-128,128)
                expected = model.feed(x)
                await bus.sample(x, gap=k%3)
                if expected is not None:
                    assert int(d.uio_out.value) & 128
                    actual = await bus.snapshot()
                    assert actual == expected, (sel, step, k, actual, expected)
                    assert not (int(d.uio_out.value) & 128)
            assert await bus.read(7) == 0
    d._log.info("32 complete blocks matched integer reference, all windows and phase wrap")


@cocotb.test()
async def protocol_and_reset(d):
    b = Bus(d)
    await b.reset()
    assert await b.read(4) == 0
    assert await b.read(5) == 16
    assert await b.read(6) == 2
    await b.configure(0, 0)
    # Sustained strobe accepts only one sample.
    d.ui_in.value=10; d.uio_in.value=1
    await b.cycle(10)
    d.uio_in.value=0; await b.cycle()
    for _ in range(15): await b.sample(10)
    assert await b.snapshot() == (1270,0)
    # Snapshot retained when a new live result arrives.
    for _ in range(16): await b.sample(20)
    assert await b.read_pair() == (1270,0)
    assert await b.snapshot() == (2540,0)
    # Trigger during busy is rejected and flagged.
    d.ui_in.value=50; d.uio_in.value=1; await b.cycle()
    d.uio_in.value=0; await b.cycle()
    d.uio_in.value=1; await b.cycle()
    d.uio_in.value=0; await b.cycle(2)
    assert (await b.read(7)) & 4
    await b.write(7,1)
    assert await b.read(7) == 0
    assert await b.snapshot() == (0,0)
    # Reconfigure while busy: discard partial operation and restart phase.
    d.ui_in.value=80; d.uio_in.value=1; await b.cycle()
    d.ui_in.value=0; d.uio_in.value=(6<<2)|2; await b.cycle()
    d.uio_in.value=0; await b.cycle(3)
    for _ in range(16): await b.sample(-128)
    assert await b.snapshot() == (-16256,0)
    # ena=0 ignores strobes; re-enable with strobes low.
    await b.write(7,1)
    d.ena.value=0
    for _ in range(16):
        d.uio_in.value=1; await b.cycle(); d.uio_in.value=0; await b.cycle(3)
    d.ena.value=1; await b.cycle()
    assert await b.read(7) == 0
    for _ in range(16): await b.sample(127)
    assert await b.snapshot() == (16129,0)
    await b.reset()
    assert await b.snapshot() == (0,0)


@cocotb.test()
async def amplitude_phase_noise_and_interference(d):
    b = Bus(d)
    await b.reset()
    rng = random.Random(77)
    for phi in (0, math.pi/2, -math.pi/3, math.pi):
        await b.configure(4096, 3)
        m = Model(4096, 1024)
        for k in range(1024):
            theta=2*math.pi*k/16
            x=round(40*math.cos(theta+phi)+20*math.cos(3*theta)+rng.gauss(0,12))
            x=max(-128,min(127,x))
            expected=m.feed(x)
            await b.sample(x)
        actual=await b.snapshot()
        assert actual==expected
        amplitude=2*math.hypot(*actual)/127
        phase=math.atan2(actual[1],actual[0])
        err=(phase-phi+math.pi)%(2*math.pi)-math.pi
        assert abs(amplitude-40)<3, amplitude
        assert abs(err)<0.12, (phase,phi)
        d._log.info("phase %.3f -> %.3f rad; amplitude 40 -> %.3f",phi,phase,amplitude)
