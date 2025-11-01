//
//  ImmersiveView.swift
//  FusenAnchorSample
//
//  Created by 酒井雄太 on 2025/10/30.
//

import SwiftUI
import RealityKit
import ARKit

struct ImmersiveView: View {
    @State private var session = ARKitSession()
    @State private var sceneReconstruction = SceneReconstructionProvider()
    @State private var meshEntities: [UUID: Entity] = [:]
    @State private var meshUpdatesTask: Task<Void, Never>?
    @State private var fusenRoot = Entity()
    @State private var meshRoot = Entity()

    var body: some View {
        RealityView { content in
            if meshRoot.parent == nil {
                content.add(meshRoot)
            }

            if fusenRoot.parent == nil {
                content.add(fusenRoot)
            }
        }
        .task {
            await startSceneReconstructionIfNeeded()
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { handleTap($0) }
        )
        .onDisappear {
            meshUpdatesTask?.cancel()
            meshUpdatesTask = nil
            meshEntities.removeAll()
            for child in Array(meshRoot.children) {
                child.removeFromParent()
            }
        }
    }

    @MainActor
    private func startSceneReconstructionIfNeeded() async {
        guard meshUpdatesTask == nil else { return }

        guard SceneReconstructionProvider.isSupported else {
            print("SceneReconstructionProvider is not supported on this device.")
            return
        }

        do {
            try await session.run([sceneReconstruction])
            meshUpdatesTask = Task { @MainActor in
                await listenForMeshUpdates()
            }
        } catch {
            print("Failed to start ARKit session: \(error)")
        }
    }

    @MainActor
    private func listenForMeshUpdates() async {
        defer {
            meshUpdatesTask = nil
        }
        for await update in sceneReconstruction.anchorUpdates {
            if Task.isCancelled { break }
            await processMeshAnchorUpdate(update)
        }
    }

    @MainActor
    private func processMeshAnchorUpdate(_ update: AnchorUpdate<MeshAnchor>) async {
        let meshAnchor = update.anchor

        guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else {
            return
        }

        switch update.event {
        case .added:
            let meshEntity = Entity()
            meshEntity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
            meshEntity.components[CollisionComponent.self] = CollisionComponent(shapes: [shape], isStatic: true)
            meshEntity.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(mode: .static)
            meshEntity.components.set(InputTargetComponent())
            meshEntities[meshAnchor.id] = meshEntity
            meshRoot.addChild(meshEntity)
        case .updated:
            guard let meshEntity = meshEntities[meshAnchor.id] else { return }
            meshEntity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
            if var collision = meshEntity.components[CollisionComponent.self] {
                collision.shapes = [shape]
                meshEntity.components[CollisionComponent.self] = collision
            }
        case .removed:
            guard let meshEntity = meshEntities.removeValue(forKey: meshAnchor.id) else { return }
            meshEntity.removeFromParent()
        }
    }

    @MainActor
    private func handleTap(_ value: EntityTargetValue<SpatialTapGesture.Value>) {
        guard meshEntities.values.contains(where: { $0 === value.entity }) else { return }

        let worldPosition = value.convert(value.location3D, from: .local, to: .scene)
        let anchor = AnchorEntity(world: worldPosition)
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.05),
            materials: [SimpleMaterial(color: .blue, isMetallic: false)]
        )
        sphere.position = .zero
        sphere.generateCollisionShapes(recursive: true)
        sphere.components.set(InputTargetComponent())
        anchor.addChild(sphere)
        fusenRoot.addChild(anchor)
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
