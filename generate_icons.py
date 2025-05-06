#!/usr/bin/env python3
from PIL import Image, ImageDraw
import os

# 确保目录存在
icon_dir = 'FileLocker/Assets.xcassets/AppIcon.appiconset'
os.makedirs(icon_dir, exist_ok=True)

# 创建512x512图标
def create_icon(size, scale=1):
    # 创建画布
    img = Image.new('RGBA', (size * scale, size * scale), color=(0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # 绘制蓝色背景
    draw.ellipse([(0, 0), (size * scale, size * scale)], fill=(0, 102, 204))
    
    # 绘制锁图标
    # 锁体
    lock_width = size * scale * 0.6
    lock_height = size * scale * 0.6
    lock_x = (size * scale - lock_width) / 2
    lock_y = (size * scale - lock_height) / 2
    
    draw.rounded_rectangle(
        [(lock_x, lock_y + lock_height * 0.4), (lock_x + lock_width, lock_y + lock_height)],
        radius=lock_width * 0.1,
        fill=(255, 255, 255)
    )
    
    # 锁环
    shackle_width = lock_width * 0.1
    draw.rectangle(
        [(lock_x + lock_width * 0.3, lock_y), (lock_x + lock_width * 0.7, lock_y + lock_height * 0.5)],
        fill=(255, 255, 255)
    )
    
    draw.rectangle(
        [(lock_x + lock_width * 0.3 - shackle_width, lock_y), 
         (lock_x + lock_width * 0.3 + shackle_width, lock_y + lock_height * 0.5)],
        fill=(255, 255, 255)
    )
    
    draw.rectangle(
        [(lock_x + lock_width * 0.7 - shackle_width, lock_y), 
         (lock_x + lock_width * 0.7 + shackle_width, lock_y + lock_height * 0.5)],
        fill=(255, 255, 255)
    )
    
    # 保存图标
    filename = f'app_icon_{size}x{size}'
    if scale > 1:
        filename += f'@{scale}x'
    filename += '.png'
    filepath = os.path.join(icon_dir, filename)
    img.save(filepath)
    print(f'生成图标: {filepath}')

# 生成所需的图标尺寸
create_icon(512, 1)  # 512x512
create_icon(512, 2)  # 512x512@2x (1024x1024)

print('图标生成完成!') 