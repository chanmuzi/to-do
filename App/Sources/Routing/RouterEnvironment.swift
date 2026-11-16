import SwiftUI

extension EnvironmentValues {
    /// SwiftUI 뷰가 쓰는 라우터. App이 뷰 계층의 뿌리에서 넣는다.
    @Entry public var router: (any Routing)? = nil
}
