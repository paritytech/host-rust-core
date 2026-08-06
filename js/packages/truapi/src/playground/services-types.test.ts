import { describe, expect, test } from "bun:test";
import { servicesForExecution, type ServiceInfo } from "./services-types.js";
import { services as generatedServices } from "./codegen/services.js";

const services: ServiceInfo[] = [
    { name: "Storage", methods: [] },
    { name: "Chat", requiredExecution: "Chat", methods: [] },
];

describe("servicesForExecution", () => {
    test("keeps shared services and services for the selected execution", () => {
        expect(servicesForExecution(services, "Spa").map(({ name }) => name)).toEqual(["Storage"]);
        expect(servicesForExecution(services, "Chat").map(({ name }) => name)).toEqual([
            "Storage",
            "Chat",
        ]);
    });

    test("generated Chat metadata carries its trusted execution requirement", () => {
        expect(generatedServices.find(({ name }) => name === "Chat")?.requiredExecution).toBe(
            "Chat",
        );
        expect(
            generatedServices.find(({ name }) => name === "Storage")?.requiredExecution,
        ).toBeUndefined();
    });
});
