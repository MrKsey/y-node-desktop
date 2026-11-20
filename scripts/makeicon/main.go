package main

// Rebuilds the 256 px master icon from the original artwork: the gradient is
// kept, the Y is scaled to 80 % of its original width and the tile gets a 25 %
// rounded corner with a one pixel antialiased edge.

import (
	"fmt"
	"image"
	"image/color"
	"image/png"
	"math"
	"os"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: makeicon <source.png> <target.png> [more targets...]")
		os.Exit(2)
	}
	source, err := readPNG(os.Args[1])
	if err != nil {
		fail(err)
	}
	out, err := rebuild(source)
	if err != nil {
		fail(err)
	}
	for _, target := range os.Args[2:] {
		if err := writePNG(target, out); err != nil {
			fail(err)
		}
		fmt.Println("wrote", target)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "makeicon:", err)
	os.Exit(1)
}

func readPNG(path string) (*image.NRGBA, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	src, err := png.Decode(file)
	if err != nil {
		return nil, err
	}
	bounds := src.Bounds()
	dst := image.NewNRGBA(image.Rect(0, 0, bounds.Dx(), bounds.Dy()))
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			dst.Set(x-bounds.Min.X, y-bounds.Min.Y, src.At(x, y))
		}
	}
	return dst, nil
}

func writePNG(path string, img image.Image) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	return png.Encode(file, img)
}

// glyphAlpha is how "warm" a pixel is: the artwork paints the Y in amber on a
// dark teal tile, so the red-over-blue difference separates the two.
func glyphAlpha(c color.NRGBA) float64 {
	warm := (float64(c.R) - float64(c.B)) / 255.0
	return math.Max(0, math.Min(1, (warm-0.15)/0.6))
}

func rebuild(source *image.NRGBA) (*image.NRGBA, error) {
	width := source.Bounds().Dx()
	height := source.Bounds().Dy()

	glyph := image.NewNRGBA(source.Bounds())
	minX, minY, maxX, maxY := width, height, -1, -1
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			c := source.NRGBAAt(x, y)
			alpha := glyphAlpha(c)
			if alpha <= 0 {
				continue
			}
			glyph.SetNRGBA(x, y, color.NRGBA{R: c.R, G: c.G, B: c.B, A: uint8(alpha * 255)})
			if alpha > 0.5 {
				minX = min(minX, x)
				minY = min(minY, y)
				maxX = max(maxX, x)
				maxY = max(maxY, y)
			}
		}
	}
	if maxX < 0 {
		return nil, fmt.Errorf("the artwork has no warm glyph")
	}
	glyphWidth := maxX - minX + 1
	glyphHeight := maxY - minY + 1

	// The background is a vertical gradient; the glyph never reaches the sides,
	// so the two edge columns give the colour of every row.
	composite := image.NewNRGBA(source.Bounds())
	for y := 0; y < height; y++ {
		left := source.NRGBAAt(6, y)
		right := source.NRGBAAt(width-7, y)
		row := color.NRGBA{
			R: uint8((int(left.R) + int(right.R)) / 2),
			G: uint8((int(left.G) + int(right.G)) / 2),
			B: uint8((int(left.B) + int(right.B)) / 2),
			A: 255,
		}
		for x := 0; x < width; x++ {
			composite.SetNRGBA(x, y, row)
		}
	}

	scale := 0.8
	drawWidth := float64(glyphWidth) * scale
	drawHeight := float64(glyphHeight) * scale
	offsetX := (float64(width) - drawWidth) / 2
	offsetY := (float64(height) - drawHeight) / 2
	blitScaled(composite, glyph, minX, minY, glyphWidth, glyphHeight, offsetX, offsetY, drawWidth, drawHeight)

	// The rounded tile: signed distance to the rounded rectangle, one pixel of
	// antialiasing at the edge.
	radius := float64(width) * 0.25
	half := float64(width) / 2
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			dx := math.Max(math.Abs(float64(x)+0.5-half)-(half-radius), 0)
			dy := math.Max(math.Abs(float64(y)+0.5-half)-(half-radius), 0)
			distance := math.Sqrt(dx*dx+dy*dy) - radius
			mask := math.Max(0, math.Min(1, 0.5-distance))
			c := composite.NRGBAAt(x, y)
			c.A = uint8(float64(c.A) * mask)
			composite.SetNRGBA(x, y, c)
		}
	}
	return composite, nil
}

// blitScaled draws a rectangular part of src into dst with bilinear filtering.
func blitScaled(dst, src *image.NRGBA, srcX, srcY, srcWidth, srcHeight int, dstX, dstY, dstWidth, dstHeight float64) {
	for y := 0; y < int(math.Ceil(dstHeight)); y++ {
		for x := 0; x < int(math.Ceil(dstWidth)); x++ {
			sx := float64(srcX) + (float64(x)+0.5)*float64(srcWidth)/dstWidth
			sy := float64(srcY) + (float64(y)+0.5)*float64(srcHeight)/dstHeight
			c := sampleBilinear(src, sx, sy)
			if c.A == 0 {
				continue
			}
			targetX := int(dstX) + x
			targetY := int(dstY) + y
			if !(image.Point{targetX, targetY}).In(dst.Bounds()) {
				continue
			}
			blend(dst, targetX, targetY, c)
		}
	}
}

func sampleBilinear(img *image.NRGBA, x, y float64) color.NRGBA {
	bounds := img.Bounds()
	x0 := int(math.Floor(x - 0.5))
	y0 := int(math.Floor(y - 0.5))
	fx := x - 0.5 - float64(x0)
	fy := y - 0.5 - float64(y0)
	at := func(px, py int) color.NRGBA {
		if px < bounds.Min.X {
			px = bounds.Min.X
		}
		if px >= bounds.Max.X {
			px = bounds.Max.X - 1
		}
		if py < bounds.Min.Y {
			py = bounds.Min.Y
		}
		if py >= bounds.Max.Y {
			py = bounds.Max.Y - 1
		}
		return img.NRGBAAt(px, py)
	}
	c00 := at(x0, y0)
	c10 := at(x0+1, y0)
	c01 := at(x0, y0+1)
	c11 := at(x0+1, y0+1)
	mix := func(a, b uint8, t float64) float64 {
		return float64(a)*(1-t) + float64(b)*t
	}
	return color.NRGBA{
		R: uint8(mix(c00.R, c10.R, fx)*(1-fy) + mix(c01.R, c11.R, fx)*fy),
		G: uint8(mix(c00.G, c10.G, fx)*(1-fy) + mix(c01.G, c11.G, fx)*fy),
		B: uint8(mix(c00.B, c10.B, fx)*(1-fy) + mix(c01.B, c11.B, fx)*fy),
		A: uint8(mix(c00.A, c10.A, fx)*(1-fy) + mix(c01.A, c11.A, fx)*fy),
	}
}

func blend(dst *image.NRGBA, x, y int, src color.NRGBA) {
	under := dst.NRGBAAt(x, y)
	sa := float64(src.A) / 255
	ba := float64(under.A) / 255
	outA := sa + ba*(1-sa)
	if outA <= 0 {
		dst.SetNRGBA(x, y, color.NRGBA{})
		return
	}
	mix := func(s, b uint8) uint8 {
		value := (float64(s)*sa + float64(b)*ba*(1-sa)) / outA
		if value > 255 {
			value = 255
		}
		return uint8(value)
	}
	dst.SetNRGBA(x, y, color.NRGBA{
		R: mix(src.R, under.R),
		G: mix(src.G, under.G),
		B: mix(src.B, under.B),
		A: uint8(outA * 255),
	})
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
