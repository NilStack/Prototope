//
//  ShapeLayer.swift
//  Prototope
//
//  Created by Jason Brennan on Mar-27-2015.
//  Copyright (c) 2015 Khan Academy. All rights reserved.
//

#if os(iOS)
	import UIKit
	typealias SystemBezierPath = UIBezierPath
#else
	import Cocoa
	typealias SystemBezierPath = NSBezierPath
#endif

/** This layer represents a 2D shape, which is drawn from a list of Segments. This class is similar to the Paths in paper.js. */
open class ShapeLayer: Layer {
	
	
	/** Creates a circle with the given center and radius. */
	convenience public init(circleCenter: Point, radius: Double, parent: Layer? = nil, name: String? = nil) {
		self.init(ovalInRectangle: Rect(
			x: circleCenter.x - radius,
			y: circleCenter.y - radius,
			width: radius * 2,
			height: radius * 2), parent: parent, name: name)
	}
	
	
	/** Creates an oval within the given rectangle. */
	convenience public init(ovalInRectangle ovalRect: Rect, parent: Layer? = nil, name: String? = nil) {
		self.init(segments: Segment.segmentsForOvalInRect(ovalRect), closed: true, parent: parent, name: name)
	}
	
	
	/** Creates a rectangle with an optional corner radius. */
	convenience public init(rectangle: Rect, cornerRadius: Double = 0, parent: Layer? = nil, name: String? = nil) {
		self.init(segments: Segment.segmentsForRect(rectangle, cornerRadius: cornerRadius), closed: true, parent: parent, name: name)
	}
	
	
	/** Creates a line from two points. */
	convenience public init(lineFromFirstPoint firstPoint: Point, toSecondPoint secondPoint: Point, parent: Layer? = nil, name: String? = nil) {
		self.init(segments: Segment.segmentsForLineFromFirstPoint(firstPoint, secondPoint: secondPoint), parent: parent, name: name)
	}
	
	
	/** Creates a regular polygon path with the given number of sides. */
	convenience public init(polygonCenteredAtPoint centerPoint: Point, radius: Double, numberOfSides: Int, parent: Layer? = nil, name: String? = nil) {
		self.init(
			segments: Segment.segmentsForPolygonCenteredAtPoint(
				Point(x: radius, y: radius),
				radius: radius,
				numberOfSides: numberOfSides
			),
			closed: true,
			parent: parent,
			name: name
		)
	}
	
	
	/** Initialize the ShapeLayer with a given path. */
	public init(segments: [Segment], closed: Bool = false, parent: Layer? = nil, name: String? = nil) {
		
		self.segments = segments
		self.closed = closed
		
		let path = ShapeLayer.bezierPathForSegments(segments, closedPath: closed)
		let bounds = Rect(path.cgPath.boundingBoxOfPath).nonInfinite()
		
		self._segmentPathCache = PathCache(path: path, bounds: bounds)
		
		super.init(parent: parent, name: name, viewClass: ShapeView.self, frame: bounds)
		
		let view = self.view as! ShapeView
		view.displayHandler = {
			// todo(jb): probably get rid of this mechanism.
			// but, I'd like to explore if it'll work (updating segments + bounds + position in this handler)
			// but for now, don't wait for the needs display loop, and just force the changes.
		}
		segmentsDidChange()
		self.shapeViewLayerStyleDidChange()
	}
	
	
	// MARK: - Segments
	
	/** A list of all segments of this path.
	Segments are in the **parent layer's** coordinate space, which feels similar to drawing tools, but is different from the default `CAShapeLayer` behaviour, which is ridiculous. */
	open var segments: [Segment] {
		didSet {
			segmentsDidChange()
		}
	}
	
	/** Private structure to hold a path and its bounds. */
	fileprivate struct PathCache {
		let path: SystemBezierPath
		let bounds: Rect
	}
	
	/** private cache of the bezier path and its bounds.
	Must be updated when the segments change. */
	fileprivate var _segmentPathCache: PathCache
	
	fileprivate func segmentsDidChange() {
		
		// essentially,
		// segments for the rect (x: 200, y: 200, width: 100, height: 100) should produce:
		// - a frame with the same rect (and position to match)
		// - those exact segments
		// - a bounds of 0, 0, 100, 100
		// and, moving that rect to say, 300, 300 (that is, moving the frame) should:
		// - move the segments accordingly
		// - keep the bounds the same
		// - also should not be allowed to change frame size
		
		// only do path math (heh) if we have segments. A zero segment path results in an infinite origin bounds :\
		let path = segments.count > 0 ? ShapeLayer.bezierPathForSegments(segments, closedPath: closed) : SystemBezierPath()
		let segmentBounds = segments.count > 0 ? Rect(path.cgPath.boundingBoxOfPath) : Rect()
		self._segmentPathCache = PathCache(path: path, bounds: segmentBounds)
		
		let renderPath = path.pathByTranslatingByDelta(segmentBounds.origin)
		shapeViewLayer.path = renderPath.cgPath
		
		self.frame = segmentBounds
	}
	
	/** Sets the layer's bounds. The given rect's size must match the size of the `segments`'s path's bounds.
	Generally speaking, you should not need to call this directly. */
	open override var bounds: Rect {
		get { return super.bounds }
		
		set {
			let pathBounds = _segmentPathCache.bounds
			
			precondition(newValue.size == pathBounds.size, "Attempting to set the shape layer's bounds to a size \(newValue.size) which doesn't match the path's size \(pathBounds.size).")
			
			super.bounds = newValue
		}
	}
	
	
	/** Sets the layer's position (by default, its centre point).
	Setting this has the effect of translating the layer's `segments` so they match the new geometry. */
	open override var position: Point {
		get { return super.position }
		
		set {
			let oldPosition = super.position
			super.position = newValue
			
			
			let pathBounds = _segmentPathCache.bounds
			
			if pathBounds.center != newValue {
				let positionDelta = newValue - oldPosition
				
				segments = segments.map {
					var segment = $0
					segment.point += positionDelta
					// todo: translate the handles, too
					return segment
				}
			}
		}
	}
	
	
	/** Sets the layer's frame. The given rect's size must match the size of the `segments`'s path's bounds.
	Setting this has the effect of translating the layer's `segments` so they match the new geometry. */
	open override var frame: Rect {
		get { return super.frame }
		
		set {
			
			let pathBounds = _segmentPathCache.bounds
			
			precondition(newValue.size == pathBounds.size, "Attempting to set the shape layer's frame to a size \(newValue.size) which doesn't match the path's size \(pathBounds.size).")
			
			let oldFrame = super.frame
			super.frame = newValue
			
			
			if pathBounds.center != newValue.center {
				let positionDelta = newValue.center - oldFrame.center
				
				segments = segments.map {
					var segment = $0
					segment.point += positionDelta
					return segment
				}
			}
		}
	}
	
	/** Gets the first segment of the path, if it exists. */
	open var firstSegment: Segment? {
		return segments.first
	}
	
	
	/** Gets the last segment of the path, if it exists. */
	open var lastSegment: Segment? {
		return segments.last
	}
	
	
	/** Convenience method to add a point by wrapping it in a segment. */
	open func addPoint(_ point: Point) {
		self.segments.append(Segment(point: point))
	}
	
	
	/** Redraws the path. You can call this after you change path segments. */
	fileprivate func setNeedsDisplay() {
		self.view.setNeedsDisplay()
	}
	
	
	// MARK: - Methods
	
	/** Returns if the the given point is enclosed within the shape. If the shape is not closed, this always returns `false`. */
	open func enclosesPoint(_ point: Point) -> Bool {
		if !self.closed {
			return false
		}
		
		let path = _segmentPathCache.path
		return path.contains(CGPoint(point))
	}
	
	
	// MARK: - Properties
	
	/** The fill colour for the shape. Defaults to `Color.black`. This is distinct from the layer's background colour. */
	open var fillColor: Color? = Color.black {
		didSet {
			shapeViewLayerStyleDidChange()
		}
	}
	
	
	/** The stroke colour for the shape. Defaults to `Color.black`. */
	open var strokeColor: Color? = Color.black {
		didSet {
			shapeViewLayerStyleDidChange()
		}
	}
	
	
	/** The width of the stroke. Defaults to 1.0. */
	open var strokeWidth = 1.0 {
		didSet {
			shapeViewLayerStyleDidChange()
		}
	}
	
	
	/** If the path is closed, the first and last segments will be connected. */
	open var closed: Bool {
		didSet {
			self.setNeedsDisplay()
		}
	}
	
	
	/** The dash length of the layer's stroke. This length is used for both the dashes and the space between dashes. Draws a solid stroke when nil. */
	open var dashLength: Double? {
		didSet {
			shapeViewLayerStyleDidChange()
		}
	}
	
	
	/** Represents the types of cap styles path segment endpoints will show. Only affects open paths. */
	public enum LineCapStyle {
		
		/** The line cap will have butts for ends. */
		case butt
		
		/** The line cap will have round ends. */
		case round
		
		/** The line cap will have square ends. */
		case square
		
		func capStyleString() -> String {
			switch self {
			case .butt:
				return kCALineCapButt
			case .round:
				return kCALineCapRound
			case .square:
				return kCALineCapSquare
			}
		}
	}
	
	
	/** The line cap style for the path. Defaults to LineCapStyle.Butt. */
	open var lineCapStyle: LineCapStyle = .butt {
		didSet {
			shapeViewLayerStyleDidChange()
		}
	}
	
	
	/** Represents the types of join styles path segments will show at their joins. */
	public enum LineJoinStyle {
		
		/** Lines will be joined with a miter style. */
		case miter
		
		/** Lines will be joined with a round style. */
		case round
		
		/** Line joins will have beveled edges. */
		case bevel
		
		func joinStyleString() -> String {
			switch self {
			case .miter:
				return kCALineJoinMiter
			case .round:
				return kCALineJoinRound
			case .bevel:
				return kCALineJoinBevel
			}
		}
	}
	
	
	/** The line join style for path lines. Defaults to LineJoinStyle.Miter. */
	open var lineJoinStyle: LineJoinStyle = .miter {
		didSet {
			shapeViewLayerStyleDidChange()
		}
	}
	
	#if os(iOS)
	// TODO: Remove this override when custom layers can inherit all the view-related Layer stuff properly.
	open override var pointInside: ((Point) -> Bool)? {
	get { return shapeView.pointInside }
	set { shapeView.pointInside = newValue }
	}
	#endif
	
	
	// MARK: - Private details
	
	fileprivate var shapeViewLayer: CAShapeLayer {
		return self.view.layer as! CAShapeLayer
	}
	
	fileprivate var shapeView: ShapeView {
		return self.view as! ShapeView
	}
	
	
	fileprivate class ShapeView: SystemView {
		var displayHandler: (() -> Void)?
		
		#if os(iOS)
		override class var layerClass : AnyClass {
		return CAShapeLayer.self
		}
		
		@objc override func display(_ layer: CALayer) {
		self.displayHandler?()
		}
		
		// TODO: This is duplicated from Layer.swift because layer subclasses with custom views
		// don't behave properly. That bug will eventually be fixed. For now, duplicate this.
		var pointInside: ((Point) -> Bool)?
		
		
		override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
		
		func defaultPointInsideImplementation(point: CGPoint, event: UIEvent?) -> Bool {
		// Try to hit test the presentation layer instead of the model layer.
		if let presentationLayer = layer.presentation() {
		let screenPoint = layer.convert(point, to: nil)
		let presentationLayerPoint = presentationLayer.convert(screenPoint, from: nil)
		return super.point(inside: presentationLayerPoint, with: event)
		} else {
		return super.point(inside: point, with: event)
		}
		}
		
		// see if the point is inside according to the default implementation
		let defaultPointInside = defaultPointInsideImplementation(point: point, event: event)
		
		// if we have a custom impl of pointInside call it, if and only if the default implementation failed.
		if let pointInside = pointInside , defaultPointInside == false {
		return pointInside(Point(point))
		} else {
		return defaultPointInside
		}
		}
		#else
		
		override var isFlipped: Bool { return true }
		
		override func makeBackingLayer() -> CALayer {
			return CAShapeLayer()
		}
		#endif
		
		override func setNeedsDisplay() {
			// The UIKit implementation (reasonably) won't call through to `CALayer` if you don't implement `drawRect:`, so we do it ourselves.
			#if os(iOS)
				self.layer.setNeedsDisplay()
			#else
				self.layer?.setNeedsDisplay()
			#endif
		}
		
		
	}
	
	
	fileprivate func shapeViewLayerStyleDidChange() {
		let layer = self.shapeViewLayer
		layer.lineCap = self.lineCapStyle.capStyleString()
		layer.lineJoin = self.lineJoinStyle.joinStyleString()
		
		if let fillColor = fillColor {
			layer.fillColor = fillColor.CGColor
		} else {
			layer.fillColor = nil
		}
		
		
		if let strokeColor = strokeColor {
			layer.strokeColor = strokeColor.CGColor
		} else {
			layer.strokeColor = nil
		}
		
		
		if let dashLength = dashLength {
			layer.lineDashPattern = [NSNumber(value: dashLength), NSNumber(value: dashLength)]
		} else {
			layer.lineDashPattern = []
		}
		
		layer.lineWidth = CGFloat(strokeWidth)
	}
	
	
	fileprivate static func bezierPathForSegments(_ segments: [Segment], closedPath: Bool) -> SystemBezierPath {
		
		/*	This is modelled on paper.js' implementation of path rendering.
		While iterating through the segments, this checks to see if a line or a curve should be drawn between them.
		Each segment has an optional handleIn and handleOut, which act as control points for curves on either side.
		See https://github.com/paperjs/paper.js/blob/1803cd216ae6b5adb6410b5e13285b0a7fc04526/src/path/Path.js#L2026
		*/
		
		let bezierPath = SystemBezierPath()
		var isFirstSegment = true
		var currentPoint = Point()
		var previousPoint = Point()
		var currentHandleIn = Point()
		var currentHandleOut = Point()
		
		func drawSegment(_ segment: Segment) {
			currentPoint = segment.point
			
			if isFirstSegment {
				bezierPath.move(to: CGPoint(currentPoint))
				isFirstSegment = false
			} else {
				if let segmentHandleIn = segment.handleIn {
					currentHandleIn = currentPoint + segmentHandleIn
				} else {
					currentHandleIn = currentPoint
				}
				
				
				if currentHandleIn == currentPoint && currentHandleOut == previousPoint {
					bezierPath.addLine(to: CGPoint(currentPoint))
				} else {
					bezierPath.addCurve(to: CGPoint(currentPoint), controlPoint1: CGPoint(currentHandleOut), controlPoint2: CGPoint(currentHandleIn))
				}
			}
			
			previousPoint = currentPoint
			if let segmentHandleOut = segment.handleOut {
				currentHandleOut = previousPoint + segmentHandleOut
			} else {
				currentHandleOut = previousPoint
			}
			
		}
		for segment in segments {
			drawSegment(segment)
		}
		
		if closedPath && segments.count > 0 {
			drawSegment(segments[0])
			bezierPath.close()
		}
		
		return bezierPath
	}
	
}

/** A segment represents a point on a path, and may optionally have control handles for a curve on either side. */
public struct Segment: CustomStringConvertible {
	
	/** The anchor point / location of this segment. */
	public var point: Point
	
	
	/** The control point going in to this segment, used when computing curves. */
	public var handleIn: Point?
	
	/** The control point coming out of this segment, used when computing curves. */
	public var handleOut: Point?
	
	
	/** Initialize a segment with the given point and optional handle points. */
	public init(point: Point, handleIn: Point? = nil, handleOut: Point? = nil) {
		self.point = point
		self.handleIn = handleIn
		self.handleOut = handleOut
	}
	
	public var description: String {
		return self.point.description
	}
}


/** Convenience functions for creating shapes. */
extension Segment {
	
	// Magic number for approximating ellipse control points.
	fileprivate static let kappa = 4.0 * (sqrt(2.0) - 1.0) / 3.0
	
	/** Creates a set of segments for drawing an oval in the given rect. Algorithm based on paper.js */
	static func segmentsForOvalInRect(_ rect: Rect) -> [Segment] {
		
		let kappaSegments = [
			Segment(point: Point(x: -1.0, y: 0.0), handleIn: Point(x: 0.0, y: kappa), handleOut: Point(x: 0.0, y: -kappa)),
			Segment(point: Point(x: 0.0, y: -1.0), handleIn: Point(x: -kappa, y: 0.0), handleOut: Point(x: kappa, y: 0.0)),
			Segment(point: Point(x: 1.0, y: 0.0), handleIn: Point(x: 0.0, y: -kappa), handleOut: Point(x: 0.0, y: kappa)),
			Segment(point: Point(x: 0.0, y: 1.0), handleIn: Point(x: kappa, y: 0.0), handleOut: Point(x: -kappa, y: 0.0))
		]
		
		var segments = [Segment]()
		let radius = Point(x: rect.size.width / 2.0, y: rect.size.height / 2.0)
		let center = rect.center
		
		for index in 0..<kappaSegments.count {
			let kappaSegment = kappaSegments[index]
			
			let point = kappaSegment.point * radius + center
			let handleIn = kappaSegment.handleIn! * radius
			let handleOut = kappaSegment.handleOut! * radius
			
			segments.append(Segment(point: point, handleIn: handleIn, handleOut: handleOut))
		}
		return segments
	}
	
	
	/** Creates a set of segments for drawing a rectangle, optionally with a corner radius. Algorithm based on paper.js */
	static func segmentsForRect(_ rect: Rect, cornerRadius radius: Double) -> [Segment] {
		var segments = [Segment]()
		
		let topLeft = rect.origin
		let topRight = Point(x: rect.maxX, y: rect.minY)
		let bottomRight = Point(x: rect.maxX, y: rect.maxY)
		let bottomLeft = Point(x: rect.minX, y: rect.maxY)
		
		
		if radius <= 0.0 {
			segments.append(Segment(point: topLeft))
			segments.append(Segment(point: topRight))
			segments.append(Segment(point: bottomRight))
			segments.append(Segment(point: bottomLeft))
		} else {
			let handle = radius * kappa
			
			segments.append(Segment(point: bottomLeft + Point(x: radius, y: 0.0), handleIn: nil, handleOut: Point(x: -1.0 * handle, y: 0)))
			segments.append(Segment(point: bottomLeft - Point(x: 0.0, y: radius), handleIn: Point(x: 0.0, y: handle), handleOut: nil))
			
			segments.append(Segment(point: topLeft + Point(x: 0.0, y: radius), handleIn: nil, handleOut: Point(x: 0.0, y: -1.0 * handle)))
			segments.append(Segment(point: topLeft + Point(x: radius, y: 0.0), handleIn: Point(x: -handle, y: 0.0), handleOut: nil))
			
			segments.append(Segment(point: topRight - Point(x: radius, y: 0.0), handleIn: nil, handleOut: Point(x: handle, y: 0)))
			segments.append(Segment(point: topRight + Point(x: 0.0, y: radius), handleIn: Point(x: 0.0, y: -handle), handleOut: nil))
			
			segments.append(Segment(point: bottomRight - Point(x: 0.0, y: radius), handleIn: nil, handleOut: Point(x: 0.0, y: handle)))
			segments.append(Segment(point: bottomRight - Point(x: radius, y: 0.0), handleIn: Point(x: handle, y: 0), handleOut: nil))
			
		}
		return segments
	}
	
	
	/** Segments for a line. Algorithm based on something I just made up. */
	static func segmentsForLineFromFirstPoint(_ firstPoint: Point, secondPoint: Point) -> [Segment] {
		return [Segment(point: firstPoint), Segment(point: secondPoint)]
	}
	
	
	/** Segments for a polygon with the given number of sides. Must be >= 3 sides or else funnybusiness ensues. */
	static func segmentsForPolygonCenteredAtPoint(_ centerPoint: Point, radius: Double, numberOfSides: Int) -> [Segment] {
		var segments = [Segment]()
		
		if numberOfSides < 3 {
			Environment.currentEnvironment?.exceptionHandler("Please use at least 3 sides for your polygon (you used \(numberOfSides))")
			return segments
		}
		
		let angle = Radian(degrees: 360.0 / Double(numberOfSides))
		let fixedRotation = -(Double.pi / 2) // By decree (and appeal to aesthetics): there should always be a vertex on top.
		
		for index in 0..<numberOfSides {
			let x = centerPoint.x + radius * cos(angle * Double(index) + fixedRotation)
			let y = centerPoint.y + radius * sin(angle * Double(index) + fixedRotation)
			segments.append(Segment(point: Point(x: x, y: y)))
		}
		
		return segments
	}
}


extension SystemBezierPath {
	
	/** Returns a copy of `path`, translated negatively by the given delta. */
	func pathByTranslatingByDelta(_ delta: Point) -> SystemBezierPath {
		let deltaCGPoint = CGPoint(delta)
		let translatedPath = self.copy() as! SystemBezierPath
		#if os(iOS)
			translatedPath.apply(CGAffineTransform(translationX: -deltaCGPoint.x, y: -deltaCGPoint.y))
		#else
			translatedPath.transform(using: AffineTransform(translationByX: -deltaCGPoint.x, byY: -deltaCGPoint.y))
		#endif
		return translatedPath
	}
	
}

#if os(macOS)
	extension SystemBezierPath {
		func addLine(to point: CGPoint) {
			line(to: point)
		}
		
		func addCurve(to point: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {
			curve(to: point, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
		}
		
		public var cgPath: CGPath {
			let path = CGMutablePath()
			var points = [CGPoint](repeating: .zero, count: 3)
			for i in 0 ..< self.elementCount {
				let type = self.element(at: i, associatedPoints: &points)
				switch type {
				case .moveToBezierPathElement:
					path.move(to: CGPoint(x: points[0].x, y: points[0].y) )
				case .lineToBezierPathElement:
					path.addLine(to: CGPoint(x: points[0].x, y: points[0].y) )
				case .curveToBezierPathElement:
					// For curveToBezierPath, the points array above comes in as:
					// [cp1, cp2, endPoint], that's why points[2] is the first arg.
					path.addCurve(to: points[2], control1: points[0], control2: points[1])
				case .closePathBezierPathElement: path.closeSubpath()
				}
			}
			return path
		}
	}
#endif

