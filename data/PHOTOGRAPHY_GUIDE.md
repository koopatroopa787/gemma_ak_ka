# Pharos: Pharmaceutical Package Photography Guide

## Overview
This guide ensures high-quality images of pharmaceutical blister packs for reliable analysis by the Pharos verification system. Clear, consistent photography is critical for accurate risk assessment.

---

## 1. Equipment Requirements

### Recommended
- **Smartphone**: Any recent model with 12MP+ rear camera (iPhone 12+, Pixel 5+, Samsung Galaxy S10+)
- **Lighting**: Natural daylight or LED ring light (5000K color temperature)
- **Stabilization**: Phone tripod or steady hand support
- **Reference**: White sheet for background

### Optional (for best results)
- Macro lens attachment (10x magnification)
- Polarizing filter to reduce glare
- Ruler/reference card for scale verification

---

## 2. Lighting Setup

### Best Practices
1. **Avoid shadows**: Position light source at 45° to package
2. **No harsh glare**: Diffuse light if using direct LED
3. **Color accuracy**: Use daylight (5000-6500K) or daylight-balanced LED
4. **Consistency**: Photograph all packages under same lighting conditions

### Lighting Configurations
| Scenario | Recommended | Why |
|----------|-------------|-----|
| Pharmacy (indoors) | LED ring light + white reflector | Consistent color, minimal shadows |
| Field (outdoor) | Overcast daylight | Soft, diffuse, no hard shadows |
| Warehouse | Dual LED panels 45° apart | Uniform illumination, no hot spots |

---

## 3. Distance & Angle Guidelines

### Optimal Framing
- **Distance**: 15-25 cm from lens to package (6-10 inches)
- **Fill frame**: Package should occupy 70-80% of image
- **Margins**: Leave 10-15% white space on all sides

### Required Angles (24+ photos per package)

#### Straight Views (4 angles)
1. **Face-on, centered**: All printed text visible
2. **Top view**: Hologram and tamper seal visible
3. **Bottom view**: Batch code on reverse side
4. **Back label**: Manufacturer, warnings, barcodes

#### Side Views (8 angles)
- Photograph each of 4 edges at 2 angles:
  - Perpendicular (90°): Shows edge condition
  - 45° tilt: Shows corner integrity and 3D text alignment

#### Diagonal Views (12 angles)
- Photograph corners at multiple angles to verify:
  - Corner sharpness and alignment
  - Color consistency at edges
  - No tampering or opening

---

## 4. Focus & Sharpness

### Critical Areas to Focus
1. **Batch code**: Smallest printed text on package
2. **Expiry date**: Typically 8-12pt font size
3. **Security features**: Hologram, microdots, holograms
4. **Text edges**: Verify crisp print (not blurred or smudged)

### Focus Technique
- **Tap text**: On smartphone, tap the batch code to focus on it
- **Lock focus**: Hold finger to lock focus before capturing
- **Wait 1 second**: Allow camera to stabilize before pressing shutter

### Quality Check Criteria
- Text should be readable by eye without zoom
- No motion blur (use tripod or stabilize hand)
- No out-of-focus areas in critical regions
- Contrast ratio: Text luminance / background luminance > 3:1

---

## 5. Color Consistency

### Color Reference
- **Include white reference**: White sheet or card in corner of shot
- **Color temperature**: Maintain consistent across all 24+ photos
- **Saturation**: Avoid over-saturated colors (indicates filters)
- **White balance**: Manual white balance if automatic drifts

### Acceptable Color Variance
- Hue: ±10° from baseline
- Saturation: ±15% from baseline
- Brightness: ±10% from baseline

---

## 6. Common Issues & Solutions

### Problem: Glare on Hologram
**Solution**: Rotate package 15-30° or use polarizing filter; reposition light source

### Problem: Batch Code Too Dark
**Solution**: Increase light intensity or use diffuser; move light closer

### Problem: Blurry Text
**Solution**: Use tripod; tap to focus on batch code; increase lighting for faster shutter speed

### Problem: Color Cast (too yellow/blue)
**Solution**: Manual white balance on white reference card; check light color temperature

### Problem: Package Tilted/Not Level
**Solution**: Use alignment guides (grid overlay in camera app); level with tripod

---

## 7. Validation with Pharos

### Run validate_dataset.py
```bash
python tests/validate_dataset.py --image-dir ./package_photos/ --label-file ./metadata.json
```

### Quality Metrics
- **Image sharpness**: Mean Laplacian > 100 (indicates sharp focus)
- **Color diversity**: Histogram coverage > 80% of color space
- **Label completeness**: All required fields present
- **Class balance**: Authentic vs suspicious ratio > 1:2

### Output Example
```
✓ Sharpness: 156 (excellent)
✓ Diversity: 94% (excellent)
✓ Labels: 100% (all fields)
✓ Balance: Authentic: 120, Suspicious: 30
Overall quality: GOOD
```

---

## 8. Metadata Recording

### Required Fields Per Photo
```json
{
  "image_path": "pharma_001_face.jpg",
  "medicine_name": "Aspirin 500mg",
  "batch_code": "GSK2024A001",
  "expiry_date": "2026-12",
  "manufacturer": "GlaxoSmithKline",
  "image_quality_ok": true,
  "risk_level": "LOW",
  "flags": [],
  "annotation": "Authentic GSK package, clear printing"
}
```

### Risk Level Classification
- **LOW**: Clear printing, intact security features, all information legible
- **MODERATE**: Minor alignment issues, slightly faded text, valid batch format
- **HIGH**: Counterfeit indicators (spelling errors, color mismatch), poor quality
- **CRITICAL**: Obvious forgery, tampered seals, illegible batch code

---

## 9. Suspicious Package Identification

### Red Flags for Counterfeits
1. **Spelling errors**: Manufacturer name, medicine name
2. **Color mismatch**: Different shade vs known genuine package
3. **Text alignment**: Misaligned printing, uneven spacing
4. **Quality degradation**: Pixelated logos, low-contrast text
5. **Missing features**: No hologram, fake tamper seal, missing barcode
6. **Batch code anomalies**: Non-matching format, invalid date, "TEST" codes
7. **Font inconsistency**: Mixed fonts or sizes (should be uniform)

### Documented Examples
Keep reference images of known counterfeits for comparison:
```
./reference/genuine/GSK_Aspirin_2024.jpg
./reference/counterfeit/GSK_Aspirin_Fake_01.jpg  (misspelled "Asprin")
./reference/counterfeit/GSK_Aspirin_Fake_02.jpg  (wrong hologram color)
```

---

## 10. Batch Photography Workflow

### Step-by-Step Process
1. **Prepare environment**: Set up lighting, background, tripod
2. **White balance**: Photograph white reference card
3. **Capture faces**: 4 straight views (front, top, bottom, back)
4. **Capture edges**: 8 side views (2 per edge)
5. **Capture corners**: 12 diagonal views (3 per corner)
6. **Validation check**: Run validate_dataset.py on subset
7. **Metadata entry**: Record all fields in JSON
8. **Archive**: Store images in organized folder structure

### Folder Structure
```
pharos_photography/
├── metadata.json
├── batch_001_GSK_Aspirin_500mg/
│   ├── face_center.jpg
│   ├── top_view.jpg
│   ├── bottom_view.jpg
│   ├── back_label.jpg
│   ├── edge_north_90.jpg
│   ├── edge_north_45.jpg
│   └── ... (16 more angle photos)
├── batch_002_Pfizer_Ibuprofen/
│   └── ... (24 photos)
└── ... (more batches)
```

---

## 11. Integration with Pharos App

### On-Device Capture
1. Pharos app opens camera with framing guides
2. Position package within guide frame (70-80% fill)
3. Ensure batch code is in focus area (tapped and locked)
4. Capture button triggers inference
5. App displays confidence score and flags

### Server Feedback
- Device sends photo + extracted metadata
- Server validates signature
- Returns risk assessment
- Stores for future fine-tuning

---

## 12. Best Practices Summary

| Rule | Reason | Impact if Violated |
|------|--------|-------------------|
| Use consistent lighting | Ensures reproducible color | Inference fails on color anomalies |
| Focus on batch code | Smallest critical text | Risk assessment accuracy drops 15-20% |
| 24+ angle coverage | Detects corner tampering | Counterfeit detection drops 30% |
| White balance reference | Color accuracy | False positives on genuine packages |
| Validate dataset quality | Prevents garbage training | Fine-tuned model accuracy drops 40% |

---

## 13. Quality Assurance Checklist

Before submitting photos for analysis:
- [ ] All 24+ angles captured
- [ ] Batch code readable at 1x zoom
- [ ] No glare on hologram/security features
- [ ] Consistent lighting across all photos
- [ ] Package level/not tilted
- [ ] Metadata complete and accurate
- [ ] validate_dataset.py shows GOOD/EXCELLENT
- [ ] No blur in critical text areas
- [ ] Color and brightness consistent across angles
- [ ] File naming follows convention

---

## 14. Troubleshooting

### "Image quality too low" error
1. Increase light brightness
2. Focus on batch code and hold
3. Use tripod for stability
4. Avoid motion blur

### "Color mismatch detected" warning
1. Check light color temperature (should be 5000-6500K)
2. Ensure white balance set correctly
3. Verify no filters applied to photos
4. Re-photograph under standard lighting

### Validation fails sharpness check
1. Ensure focus is on batch code
2. Use tripod or stabilize camera
3. Avoid hand shake
4. Use image stabilization mode if available

---

## Contact & Support

For questions about photography quality or Pharos analysis:
- Email: pharos-support@example.com
- Issues: [GitHub Issues](https://github.com/pharos-verify/pharos)
- Documentation: [Pharos Wiki](https://github.com/pharos-verify/pharos/wiki)

---

**Last Updated**: 2024 | **Version**: 1.0
