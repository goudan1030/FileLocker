import SwiftUI

/// 通用步骤视图组件
public struct StepView: View {
    let number: Int
    let text: String
    
    public init(number: Int, text: String) {
        self.number = number
        self.text = text
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 15) {
            // 步骤编号圆圈
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Text("\(number)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.blue)
            }
            
            // 步骤文本
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true) // 允许文本换行
            
            Spacer()
        }
    }
} 