import CoreGraphics

extension Theme {
    public func space(_ token: SpaceToken) -> CGFloat { tokens.space(token) }
    public func shape(_ token: ShapeToken) -> CGFloat { tokens.shape(token) }
    public func component(_ token: ComponentToken) -> CGFloat { tokens.component(token) }
    public func ratio(_ token: RatioToken) -> Double { tokens.ratio(token) }
    public func count(_ token: CountToken) -> Int { tokens.count(token) }
    public var docPadding: ThemeInsets { tokens.docPadding }
    public var material: MaterialTokens { tokens.material }
    public var motion: MotionTokens { tokens.motion }
    public var palette: [PaletteColor] { tokens.palette }
    public var accentPresets: [AccentPreset] { tokens.accentPresets }
}
